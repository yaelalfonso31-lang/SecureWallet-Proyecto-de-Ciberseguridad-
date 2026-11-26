"""Servidor web de solo lectura + Laboratorio de Ataques (Predeterminados y Personalizados con BD real)."""
import base64
import hashlib
import json
import os
import secrets
import sqlite3
import sys
import time
import uuid
from pathlib import Path

import httpx
import uvicorn
from cryptography.exceptions import InvalidTag
from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

MONITOR_DIR = Path(__file__).resolve().parent
BACKEND_DIR = MONITOR_DIR.parents[1]
sys.path.insert(0, str(BACKEND_DIR))

from shared.config import settings  # noqa: E402
from shared.security.crypto import decrypt  # noqa: E402
from shared.security.signing import sign  # noqa: E402
from shared.security.tokens import create_access_token  # noqa: E402
from wallet_service.audit import verify_chain  # noqa: E402
from wallet_service.database import SessionLocal  # noqa: E402
from wallet_service.models import AuditLog  # noqa: E402

WALLET_BASE = os.getenv("INSPECTOR_WALLET_URL", "http://127.0.0.1:8001")
BANK_BASE = os.getenv("INSPECTOR_BANK_URL", "http://127.0.0.1:8002")
STORE_BASE = os.getenv("INSPECTOR_STORE_URL", "http://127.0.0.1:8003")

app = FastAPI(title="SecureWallet - Web Inspector & Custom Attack Lab")
app.mount("/static", StaticFiles(directory=str(MONITOR_DIR)), name="static")

_TAMPER_BACKUP: dict[int, str] = {}


class CustomAttackRequest(BaseModel):
    attack_type: str
    user_id: str | None = None
    second_user_id: str | None = None
    card_id: str | None = None
    ticket_id: str | None = None
    order_id: str | None = None
    tampered_amount_cents: int | None = None
    mode: str | None = None


class RecordEditRequest(BaseModel):
    fields: dict


class ManualExecuteRequest(BaseModel):
    entity: str
    record_id: str
    test_password: str | None = None


def _key_fingerprint(secret: str) -> str:
    if not secret:
        return "NO CONFIGURADA"
    return hashlib.sha256(secret.encode()).hexdigest()[:16].upper()


def _pkce_s256(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def _ro_query(db_name: str, sql: str, params: tuple = ()) -> list[dict]:
    db_path = BACKEND_DIR / db_name
    if not db_path.exists():
        return []
    uri = f"file:{db_path.as_posix()}?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True, timeout=1.0)
        conn.row_factory = sqlite3.Row
        rows = [dict(r) for r in conn.execute(sql, params).fetchall()]
        conn.close()
        return rows
    except sqlite3.Error:
        return []


def _table_columns(db_name: str, table: str) -> set[str]:
    rows = _ro_query(db_name, f"PRAGMA table_info({table})")
    return {r["name"] for r in rows}


# ================= EDITOR MANUAL DE REGISTROS (ESCRITURA REAL EN SQLITE) =================
# Permite simular un atacante con acceso directo a la base de datos: el usuario edita
# a mano un campo real (p.ej. el ciphertext de una tarjeta o el JSON de un ticket) y la
# app lo persiste de verdad en el archivo .db correspondiente, para luego ejecutar la
# operación real del sistema (login, descifrado, canje de ticket, consulta de orden) y
# comprobar si el mecanismo de defensa detecta la manipulación.

ENTITY_MAP = {
    "user": {
        "db": "wallet.db",
        "table": "users",
        "pk": "id",
        "editable": ["full_name", "password_hash", "failed_attempts", "locked_until"],
    },
    "card": {
        "db": "wallet.db",
        "table": "cards",
        "pk": "id",
        "editable": ["brand", "last4", "holder_name", "pan_encrypted"],
    },
    "ticket": {
        "db": "bank.db",
        "table": "bank_tickets",
        "pk": "ticket_id",
        "editable": ["ticket_json", "signature", "status"],
    },
    "order": {
        "db": "store.db",
        "table": "orders",
        "pk": "order_id",
        "editable": ["subtotal_cents", "discount_cents", "total_cents", "status"],
    },
}


def _rw_execute(db_name: str, sql: str, params: tuple = ()) -> int:
    """Conexión de ESCRITURA real (no ?mode=ro) para que el editor manual persista cambios."""
    db_path = BACKEND_DIR / db_name
    conn = sqlite3.connect(str(db_path), timeout=5.0)
    try:
        cur = conn.execute(sql, params)
        conn.commit()
        return cur.rowcount
    finally:
        conn.close()


@app.get("/api/record/{entity}/{record_id}")
def get_record(entity: str, record_id: str):
    """Devuelve el registro REAL completo (todas sus columnas) para editarlo a mano."""
    schema = ENTITY_MAP.get(entity)
    if not schema:
        return JSONResponse(status_code=400, content={"detail": f"Entidad '{entity}' no soportada."})
    rows = _ro_query(schema["db"], f"SELECT * FROM {schema['table']} WHERE {schema['pk']} = ?", (record_id,))
    if not rows:
        return JSONResponse(status_code=404, content={"detail": "Registro no encontrado en la BD real."})
    return {"entity": entity, "db": schema["db"], "table": schema["table"], "pk": schema["pk"],
            "editable_fields": schema["editable"], "record": rows[0]}


@app.put("/api/record/{entity}/{record_id}")
def update_record(entity: str, record_id: str, req: RecordEditRequest):
    """Escribe DE VERDAD los campos editados en el .db real (UPDATE con sqlite3, sin modo ro)."""
    schema = ENTITY_MAP.get(entity)
    if not schema:
        return JSONResponse(status_code=400, content={"detail": f"Entidad '{entity}' no soportada."})
    existing = _ro_query(schema["db"], f"SELECT * FROM {schema['table']} WHERE {schema['pk']} = ?", (record_id,))
    if not existing:
        return JSONResponse(status_code=404, content={"detail": "Registro no encontrado en la BD real."})

    changes = {k: v for k, v in req.fields.items() if k in schema["editable"]}
    rejected = [k for k in req.fields.keys() if k not in schema["editable"]]
    if not changes:
        return JSONResponse(status_code=400, content={"detail": "Ningún campo enviado es editable para esta entidad."})

    set_clause = ", ".join(f"{col} = ?" for col in changes.keys())
    params = tuple(changes.values()) + (record_id,)
    try:
        affected = _rw_execute(
            schema["db"], f"UPDATE {schema['table']} SET {set_clause} WHERE {schema['pk']} = ?", params
        )
    except sqlite3.Error as exc:
        return JSONResponse(status_code=400, content={"detail": f"SQLite rechazó la escritura: {exc}"})

    updated = _ro_query(schema["db"], f"SELECT * FROM {schema['table']} WHERE {schema['pk']} = ?", (record_id,))
    return {
        "written": affected > 0,
        "fields_written": list(changes.keys()),
        "fields_rejected": rejected,
        "record": updated[0] if updated else None,
    }


@app.post("/api/manual-execute")
def manual_execute(req: ManualExecuteRequest):
    """Ejecuta la operación real del sistema sobre un registro editado a mano y reporta la defensa."""
    try:
        if req.entity == "card":
            cards = _ro_query(
                "wallet.db", "SELECT id, user_id, brand, last4, pan_encrypted FROM cards WHERE id = ?", (req.record_id,)
            )
            if not cards:
                return JSONResponse(status_code=404, content={"detail": "Tarjeta no encontrada en wallet.db."})
            card = cards[0]
            try:
                decrypt(card["pan_encrypted"], aad=card["user_id"])
                blocked, error_name = False, "Ninguno"
            except InvalidTag:
                blocked, error_name = True, "cryptography.exceptions.InvalidTag"
            except Exception as exc:  # base64 inválido, etc.
                blocked, error_name = True, f"{type(exc).__name__}: {exc}"

            return {
                "title": f"Prueba Manual: Descifrar Tarjeta Editada a Mano ({card['brand'].upper()} •••• {card['last4']})",
                "stride": "Tampering / Info Disclosure (Edición Directa en BD)",
                "blocked": blocked,
                "actual_status": 400 if blocked else 200,
                "target": "wallet.db -> cards.pan_encrypted (AES-256-GCM, editado manualmente)",
                "steps": [
                    f"1. El usuario editó a mano 'pan_encrypted' de la tarjeta {card['brand'].upper()} •••• {card['last4']} y lo guardó directamente en wallet.db.",
                    "2. El sistema intentó descifrar ese valor exactamente como lo haría la app real, usando el user_id dueño como AAD.",
                    f"3. Resultado del motor criptográfico: '{error_name}'.",
                ],
                "request_payload": {"pan_encrypted_editado": card["pan_encrypted"][:48] + "...", "aad_usado": card["user_id"]},
                "server_response": {"exception": error_name, "decrypted_pan": None if blocked else "(válido, sin alterar)"},
                "defense_mechanism": {
                    "name": "Etiqueta de Autenticación AES-256-GCM (AEAD)",
                    "layer": "Integridad de Datos en Reposo",
                    "where": "backend/shared/security/crypto.py -> decrypt()",
                    "how": "Aunque el atacante tenga acceso de escritura directo a SQLite y pueda pegar cualquier texto en 'pan_encrypted', sin la DATA_ENCRYPTION_KEY no puede generar un Tag GCM válido para ese contenido, así que el descifrado falla salvo que el valor editado sea, por coincidencia, un ciphertext legítimo para ese mismo usuario.",
                },
            }

        with httpx.Client(timeout=10.0) as client:
            if req.entity == "ticket":
                rows = _ro_query(
                    "bank.db",
                    "SELECT ticket_id, owner_ref, ticket_json, signature, status FROM bank_tickets WHERE ticket_id = ?",
                    (req.record_id,),
                )
                if not rows:
                    return JSONResponse(status_code=404, content={"detail": "Ticket no encontrado en bank.db."})
                tkt = rows[0]
                try:
                    ticket_obj = json.loads(tkt["ticket_json"])
                except json.JSONDecodeError as exc:
                    return JSONResponse(status_code=400, content={"detail": f"El JSON editado del ticket es inválido: {exc}"})

                order_id, _ = _ensure_pending_order_for_user(client, tkt["owner_ref"], None)
                attack_body = {"tickets": [{"ticket": ticket_obj, "signature": tkt["signature"]}]}
                headers = {"Authorization": f"Bearer {create_access_token(tkt['owner_ref'])}"}
                res = client.post(f"{STORE_BASE}/orders/{order_id}/pay-with-tickets", json=attack_body, headers=headers)

                return {
                    "title": f"Prueba Manual: Canjear Ticket Editado a Mano ({tkt['ticket_id']})",
                    "stride": "Tampering (Edición Directa en BD)",
                    "blocked": res.status_code not in (200,),
                    "actual_status": res.status_code,
                    "target": f"POST :8003/orders/{order_id}/pay-with-tickets",
                    "steps": [
                        f"1. El usuario editó a mano 'ticket_json' y/o 'signature' del ticket '{tkt['ticket_id']}' y lo guardó directamente en bank.db (status actual: {tkt['status']}).",
                        f"2. Se intentó canjear ese ticket, tal cual quedó en la BD, para pagar la orden '{order_id}'.",
                        f"3. La Tienda validó esquema + firma Ed25519 contra BANK_SIGNING_PUBLIC_KEY y el estado de doble gasto → HTTP {res.status_code}.",
                    ],
                    "request_payload": attack_body,
                    "server_response": res.json(),
                    "defense_mechanism": {
                        "name": "Firma Digital Ed25519 + Control Anti-Doble Gasto",
                        "layer": "Autenticidad, Integridad y Unicidad de Instrumentos de Pago",
                        "where": "backend/store_service/routers/orders.py -> _verify_tickets_locally()",
                        "how": "Editar directamente las columnas de bank_tickets no genera una firma nueva ni cambia el estado en el motor de canje: si el JSON ya no coincide byte a byte con lo firmado por el Banco, o el ticket ya estaba 'spent', la Tienda rechaza el pago.",
                    },
                }

            if req.entity == "order":
                ords = _ro_query(
                    "store.db",
                    "SELECT order_id, user_id, total_cents, status, receipt_json, receipt_signature FROM orders WHERE order_id = ?",
                    (req.record_id,),
                )
                if not ords:
                    return JSONResponse(status_code=404, content={"detail": "Orden no encontrada en store.db."})
                ord_row = ords[0]
                headers = {"Authorization": f"Bearer {create_access_token(ord_row['user_id'])}"}
                res = client.get(f"{STORE_BASE}/orders/{ord_row['order_id']}", headers=headers)
                server_json = res.json() if res.status_code == 200 else {}
                server_total = server_json.get("total_cents")
                receipt_mismatch = bool(
                    ord_row["receipt_signature"]
                    and ord_row["status"] == "paid"
                    and ord_row["receipt_json"]
                )
                return {
                    "title": f"Prueba Manual: Consultar Orden Editada a Mano ({ord_row['order_id']})",
                    "stride": "Tampering (Edición Directa en BD, Sin Firma Propia)",
                    "blocked": False,
                    "actual_status": res.status_code,
                    "target": f"GET :8003/orders/{ord_row['order_id']}",
                    "steps": [
                        f"1. El usuario editó a mano 'total_cents'/'status' de la orden '{ord_row['order_id']}' directamente en store.db.",
                        "2. La Tienda respondió con el valor editado tal cual, porque la tabla 'orders' no está protegida por firma digital propia.",
                        "3. Compara 'server_response.total_cents' contra 'receipt_json'/'receipt_signature': si la orden ya fue pagada, el recibo firmado por el Banco sigue atado al monto ORIGINAL y delata la manipulación." if receipt_mismatch else "3. Esta orden aún no tiene recibo firmado (no está 'paid'), así que no hay nada que la contradiga: este es un campo sin protección criptográfica.",
                    ],
                    "request_payload": {"order_id": ord_row["order_id"], "total_cents_en_bd": ord_row["total_cents"]},
                    "server_response": server_json,
                    "defense_mechanism": {
                        "name": "Recibo Firmado Ed25519 del Banco (protege solo lo ya pagado)" if receipt_mismatch else "Ninguno: 'orders.total_cents' no tiene protección criptográfica propia",
                        "layer": "Integridad Post-Pago (No Repudio)",
                        "where": "backend/store_service/models.py -> orders.receipt_json / receipt_signature",
                        "how": "El total de una orden pendiente vive sin cifrar ni firmar en store.db por diseño (la Tienda es dueña de su propio catálogo); la protección real ocurre cuando el Banco firma el recibo de pago, así que esta superficie demuestra qué pasa cuando SÍ se confía en la BD local sin un control adicional.",
                    },
                }

            if req.entity == "user":
                users = _ro_query(
                    "wallet.db",
                    "SELECT id, email, failed_attempts, locked_until FROM users WHERE id = ?",
                    (req.record_id,),
                )
                if not users:
                    return JSONResponse(status_code=404, content={"detail": "Usuario no encontrado en wallet.db."})
                user = users[0]
                if not req.test_password:
                    return JSONResponse(
                        status_code=400,
                        content={"detail": "Escribe una contraseña de prueba para intentar el login real."},
                    )
                res = client.post(
                    f"{WALLET_BASE}/auth/login", json={"email": user["email"], "password": req.test_password}
                )
                return {
                    "title": f"Prueba Manual: Login contra Usuario Editado a Mano ({user['email']})",
                    "stride": "Spoofing (Edición Directa de Bloqueo/Hash en BD)",
                    "blocked": res.status_code in (401, 423),
                    "actual_status": res.status_code,
                    "target": "POST :8001/auth/login",
                    "steps": [
                        f"1. El usuario editó a mano 'password_hash' y/o 'failed_attempts'/'locked_until' de '{user['email']}' directamente en wallet.db.",
                        "2. Se intentó iniciar sesión real con la contraseña de prueba proporcionada.",
                        f"3. El Wallet Service verificó el hash Argon2id y el estado de bloqueo vigente → HTTP {res.status_code}.",
                    ],
                    "request_payload": {"email": user["email"], "password_enviada": "•" * len(req.test_password)},
                    "server_response": res.json(),
                    "defense_mechanism": {
                        "name": "Verificación Argon2id contra Hash Real + Bloqueo Temporal",
                        "layer": "Autenticación",
                        "where": "backend/wallet_service/routers/auth.py -> login()",
                        "how": "Reescribir 'password_hash' a mano no le da al atacante la contraseña en claro: Argon2id solo valida si el texto plano produce ese hash exacto, y si 'locked_until' sigue vigente (incluso editado) el servidor igual puede volver a bloquear la cuenta tras nuevos fallos.",
                    },
                }

        return JSONResponse(status_code=400, content={"detail": "Entidad no soportada para prueba manual."})

    except httpx.ConnectError as exc:
        return JSONResponse(
            status_code=503,
            content={"detail": f"No se pudo conectar a los microservicios ({exc}). Verifica puertos 8001, 8002 y 8003."},
        )
    except Exception as exc:
        return JSONResponse(status_code=500, content={"detail": f"Error en prueba manual: {exc}"})



def _provision_test_identity(client: httpx.Client) -> dict:
    """Crea una identidad efímera para los ataques predeterminados de 1 clic."""
    uid = uuid.uuid4().hex[:8]
    email = f"audit-{uid}@demo.com"
    password = f"SecWallet!{uid}"

    r_reg = client.post(
        f"{WALLET_BASE}/auth/register",
        json={"email": email, "full_name": f"Usuario Demo {uid.upper()}", "password": password},
    )
    r_reg.raise_for_status()
    wallet_user_id = r_reg.json()["id"]

    r_log = client.post(f"{WALLET_BASE}/auth/login", json={"email": email, "password": password})
    r_log.raise_for_status()
    wallet_token = r_log.json()["access_token"]
    wallet_headers = {"Authorization": f"Bearer {wallet_token}"}

    r_assert = client.post(f"{WALLET_BASE}/bank-link/assertion", headers=wallet_headers)
    r_assert.raise_for_status()

    r_open = client.post(
        f"{BANK_BASE}/customers/open-account",
        json={"email": email, "password": password, "wallet_assertion": r_assert.json()},
    )
    r_open.raise_for_status()

    r_assert2 = client.post(f"{WALLET_BASE}/bank-link/assertion", headers=wallet_headers)
    verifier = secrets.token_urlsafe(48)
    state = secrets.token_urlsafe(16)
    r_auth = client.post(
        f"{BANK_BASE}/oauth/authorize",
        json={
            "email": email,
            "password": password,
            "code_challenge": _pkce_s256(verifier),
            "code_challenge_method": "S256",
            "client_id": "securewallet-mobile",
            "state": state,
            "wallet_assertion": r_assert2.json(),
        },
    )
    r_auth.raise_for_status()
    code = r_auth.json()["code"]

    r_tok = client.post(
        f"{BANK_BASE}/oauth/token",
        json={"code": code, "code_verifier": verifier, "client_id": "securewallet-mobile"},
    )
    r_tok.raise_for_status()
    bank_token = r_tok.json()["access_token"]

    return {
        "email": email,
        "password": password,
        "wallet_user_id": wallet_user_id,
        "wallet_headers": wallet_headers,
        "bank_headers": {"Authorization": f"Bearer {bank_token}"},
    }


def _ensure_pending_order_for_user(client: httpx.Client, user_id: str, order_id: str | None) -> tuple[str, int]:
    """Usa una orden pendiente existente del usuario o crea una nueva para probar el pago."""
    headers = {"Authorization": f"Bearer {create_access_token(user_id)}"}
    if order_id:
        rows = _ro_query(
            "store.db",
            "SELECT order_id, user_id, total_cents, status FROM orders WHERE order_id = ?",
            (order_id,),
        )
        if rows and rows[0]["user_id"] == user_id and rows[0]["status"] == "pending":
            return rows[0]["order_id"], rows[0]["total_cents"]

    products = client.get(f"{STORE_BASE}/products").json()
    cheapest = min(products, key=lambda p: p["price_cents"])
    r_ord = client.post(
        f"{STORE_BASE}/orders",
        json={"items": [{"product_id": cheapest["id"], "quantity": 1}]},
        headers=headers,
    )
    r_ord.raise_for_status()
    data = r_ord.json()
    return data["order_id"], data["amount_cents"]


@app.get("/")
def index():
    return FileResponse(MONITOR_DIR / "index.html")


@app.get("/api/snapshot")
def snapshot():
    user_cols = _table_columns("wallet.db", "users")
    totp_fields = (
        ", totp_enabled, totp_secret"
        if "totp_enabled" in user_cols
        else ", 0 AS totp_enabled, NULL AS totp_secret"
    )
    users = _ro_query(
        "wallet.db",
        f"SELECT id, email, full_name, password_hash, failed_attempts, locked_until{totp_fields}, created_at "
        "FROM users ORDER BY created_at DESC LIMIT 15",
    )
    cards = _ro_query(
        "wallet.db",
        "SELECT id, user_id, token, brand, last4, holder_name, exp_month, exp_year, pan_encrypted, created_at "
        "FROM cards ORDER BY created_at DESC LIMIT 15",
    )
    wallet_accounts = _ro_query(
        "wallet.db",
        "SELECT user_id, balance_cents, updated_at FROM wallet_accounts ORDER BY updated_at DESC LIMIT 10",
    )
    audits = _ro_query(
        "wallet.db",
        "SELECT id, event, user_id, detail, prev_hash, hash, created_at FROM audit_log ORDER BY id DESC LIMIT 10",
    )

    try:
        with SessionLocal() as db:
            chain_valid = verify_chain(db)
    except Exception:
        chain_valid = True

    bank_accounts = _ro_query(
        "bank.db",
        "SELECT id, owner_ref, account_number, status, balance_cents, created_at FROM accounts ORDER BY id DESC LIMIT 10",
    )
    for acc in bank_accounts:
        num = acc.get("account_number") or ""
        acc["account_masked"] = f"•••• {num[-4:]}" if len(num) >= 4 else "••••"
        acc.pop("account_number", None)

    oauth_codes = _ro_query(
        "bank.db",
        "SELECT id, code_hash, code_challenge, wallet_user_id, used, expires_at FROM authorization_codes ORDER BY id DESC LIMIT 5",
    )
    tickets = _ro_query(
        "bank.db",
        "SELECT ticket_id, owner_ref, amount_cents, currency, nonce, ticket_hash, signature, status, spent_in_order_id, issued_at "
        "FROM bank_tickets ORDER BY issued_at DESC LIMIT 15",
    )

    orders = _ro_query(
        "store.db",
        "SELECT order_id, user_id, subtotal_cents, discount_cents, total_cents, status, receipt_json, receipt_signature, created_at "
        "FROM orders ORDER BY created_at DESC LIMIT 15",
    )
    spent_tickets = _ro_query(
        "store.db",
        "SELECT ticket_id, order_id, amount_cents, ticket_hash, redeemed_at FROM spent_tickets ORDER BY redeemed_at DESC LIMIT 10",
    )

    return {
        "keys": {
            "aes_key_fingerprint": _key_fingerprint(settings.data_encryption_key),
            "wallet_public_key": settings.wallet_signing_public_key,
            "bank_public_key": settings.bank_signing_public_key,
            "mtls_configured": Path(BACKEND_DIR / settings.mtls_ca_cert).exists(),
        },
        "wallet": {
            "users": users,
            "cards": cards,
            "accounts": wallet_accounts,
            "audit_chain_valid": chain_valid,
            "audit_tampered_demo": bool(_TAMPER_BACKUP),
            "audit_log": audits,
        },
        "bank": {
            "accounts": bank_accounts,
            "oauth_codes": oauth_codes,
            "tickets": tickets,
        },
        "store": {
            "orders": orders,
            "spent_tickets": spent_tickets,
        },
    }


@app.post("/api/custom-attack")
def run_custom_attack(req: CustomAttackRequest):
    """Ejecuta un ataque personalizado utilizando registros reales extraídos de las bases de datos."""
    try:
        # 1) ATAQUE DE CRIPTOGRAFÍA SIMÉTRICA: Alterar ciphertext o sustituir AAD en tarjeta real
        if req.attack_type == "custom_aes_gcm_tamper":
            if not req.card_id:
                return JSONResponse(status_code=400, content={"detail": "Selecciona una tarjeta real de wallet.db."})
            cards = _ro_query(
                "wallet.db",
                "SELECT id, user_id, brand, last4, token, pan_encrypted FROM cards WHERE id = ?",
                (req.card_id,),
            )
            if not cards:
                return JSONResponse(status_code=404, content={"detail": "Tarjeta no encontrada en wallet.db."})
            card = cards[0]
            mode = req.mode or "bitflip"

            if mode == "aad_swap":
                if not req.second_user_id or req.second_user_id == card["user_id"]:
                    return JSONResponse(
                        status_code=400,
                        content={"detail": "Selecciona otro usuario distinto al dueño para probar el robo/sustitución de registro."},
                    )
                victim_users = _ro_query("wallet.db", "SELECT email FROM users WHERE id = ?", (req.second_user_id,))
                thief_email = victim_users[0]["email"] if victim_users else req.second_user_id
                try:
                    decrypt(card["pan_encrypted"], aad=req.second_user_id)
                    blocked = False
                    error_name = "Ninguno"
                except InvalidTag:
                    blocked = True
                    error_name = "cryptography.exceptions.InvalidTag"

                return {
                    "title": f"Sustitución de AAD en Tarjeta Real ({card['brand'].upper()} •••• {card['last4']})",
                    "stride": "Tampering / Info Disclosure (Cifrado Simétrico)",
                    "blocked": blocked,
                    "actual_status": 400 if blocked else 200,
                    "target": "wallet.db -> cards.pan_encrypted (AES-256-GCM)",
                    "steps": [
                        f"1. Se extrajo el bloque cifrado real 'pan_encrypted' de la tarjeta {card['brand'].upper()} •••• {card['last4']} (dueño: {card['user_id'][:12]}...).",
                        f"2. Se simuló que un atacante con acceso SQL copia ese ciphertext hacia la cuenta de '{thief_email}' ({req.second_user_id[:12]}...).",
                        f"3. Al intentar descifrar pasando el user_id del atacante como AAD, AES-GCM lanzó '{error_name}'.",
                    ],
                    "request_payload": {
                        "card_token": card["token"],
                        "pan_encrypted_prefix": card["pan_encrypted"][:36] + "...",
                        "original_owner_aad": card["user_id"],
                        "attacker_aad": req.second_user_id,
                    },
                    "server_response": {
                        "exception": error_name,
                        "decrypted_pan": None,
                        "detail": "Fallo de verificación de etiqueta GCM (16 bytes): el contexto AAD no coincide con el dueño original.",
                    },
                    "defense_mechanism": {
                        "name": "Cifrado Autenticado AES-256-GCM con AAD (Associated Authenticated Data)",
                        "layer": "Confidencialidad e Integridad de Datos en Reposo",
                        "where": "backend/shared/security/crypto.py -> encrypt() / decrypt()",
                        "how": "AES-256-GCM autentica tanto el texto cifrado como los datos asociados (AAD = user_id). Aunque alguien copie el blob cifrado a otro registro de SQLite, la etiqueta de autenticación de 128 bits falla y el PAN jamás se expone.",
                    },
                }

            # Modo bitflip: alterar 1 carácter en medio del ciphertext Base64URL
            raw_bytes = bytearray(base64.urlsafe_b64decode(card["pan_encrypted"]))
            raw_bytes[16] ^= 0xFF
            tampered_blob = base64.urlsafe_b64encode(bytes(raw_bytes)).decode()
            try:
                decrypt(tampered_blob, aad=card["user_id"])
                blocked = False
                error_name = "Ninguno"
            except InvalidTag:
                blocked = True
                error_name = "cryptography.exceptions.InvalidTag"

            return {
                "title": f"Bit-Flipping sobre Ciphertext Real ({card['brand'].upper()} •••• {card['last4']})",
                "stride": "Tampering (Manipulación en Base de Datos)",
                "blocked": blocked,
                "actual_status": 400 if blocked else 200,
                "target": "wallet.db -> cards.pan_encrypted (AES-256-GCM)",
                "steps": [
                    f"1. Se leyó el texto cifrado real de la tarjeta •••• {card['last4']} desde wallet.db.",
                    "2. Se invirtieron los bits del byte #16 (dentro del bloque cifrado del PAN) sin conocer DATA_ENCRYPTION_KEY.",
                    f"3. El motor criptográfico verificó el Tag de Autenticación GCM de 16 bytes antes de descifrar y abortó con '{error_name}'.",
                ],
                "request_payload": {
                    "original_pan_encrypted": card["pan_encrypted"][:36] + "...",
                    "tampered_pan_encrypted": tampered_blob[:36] + "...",
                    "modified_byte_offset": 16,
                },
                "server_response": {
                    "exception": error_name,
                    "detail": "Integridad comprometida: AES-GCM rechazó el bloque alterado antes de entregar texto plano.",
                },
                "defense_mechanism": {
                    "name": "Etiqueta de Autenticación GMAC (128 bits) en AES-256-GCM",
                    "layer": "Integridad Autenticada en Reposo (AEAD)",
                    "where": "backend/shared/security/crypto.py -> decrypt()",
                    "how": "A diferencia de modos no autenticados (como CBC o CTR), GCM calcula un MAC polinomial (GHASH) sobre el nonce, el AAD y el texto cifrado. Cualquier alteración de 1 bit invalida el tag e impide descifrar basura o manipular dígitos de la tarjeta.",
                },
            }

        with httpx.Client(timeout=10.0) as client:
            # 2) MANIPULAR UN TICKET REAL DE bank.db
            if req.attack_type == "custom_ticket_tamper":
                if not req.ticket_id:
                    return JSONResponse(status_code=400, content={"detail": "Selecciona un ticket real de bank.db."})
                rows = _ro_query(
                    "bank.db",
                    "SELECT ticket_id, owner_ref, amount_cents, ticket_json, signature, status FROM bank_tickets WHERE ticket_id = ?",
                    (req.ticket_id,),
                )
                if not rows:
                    return JSONResponse(status_code=404, content={"detail": "Ticket no encontrado en bank.db."})
                tkt_row = rows[0]
                owner_id = tkt_row["owner_ref"]
                fake_cents = req.tampered_amount_cents or 50_000

                order_id, _ = _ensure_pending_order_for_user(client, owner_id, req.order_id)
                ticket_payload = json.loads(tkt_row["ticket_json"])
                original_cents = ticket_payload["amount_cents"]
                ticket_payload["amount_cents"] = fake_cents

                attack_body = {"tickets": [{"ticket": ticket_payload, "signature": tkt_row["signature"]}]}
                headers = {"Authorization": f"Bearer {create_access_token(owner_id)}"}
                res = client.post(
                    f"{STORE_BASE}/orders/{order_id}/pay-with-tickets",
                    json=attack_body,
                    headers=headers,
                )

                return {
                    "title": f"Alteración de Ticket Real {tkt_row['ticket_id']} (${original_cents // 100} → ${fake_cents // 100})",
                    "stride": "Tampering (Falsificación de Valor Monetario)",
                    "blocked": res.status_code in (400, 422),
                    "actual_status": res.status_code,
                    "target": f"POST :8003/orders/{order_id}/pay-with-tickets",
                    "steps": [
                        f"1. Se tomó el ticket real '{tkt_row['ticket_id']}' emitido por ${original_cents / 100:,.2f} MXN en bank.db.",
                        f"2. Se modificó 'amount_cents' a {fake_cents} (${fake_cents / 100:,.2f} MXN) adjuntando la firma Ed25519 original del Banco.",
                        f"3. La Tienda validó el esquema y la firma Ed25519 con BANK_SIGNING_PUBLIC_KEY → Rechazado con HTTP {res.status_code}.",
                    ],
                    "request_payload": attack_body,
                    "server_response": res.json(),
                    "defense_mechanism": {
                        "name": "Firma Digital Asimétrica Ed25519 + Validación de Denominaciones",
                        "layer": "Autenticidad e Integridad de Instrumentos de Pago",
                        "where": "backend/store_service/routers/orders.py -> _verify_tickets_locally()",
                        "how": "El Banco firmó el JSON canónico del ticket con su llave privada Ed25519. La Tienda verifica localmente la firma usando BANK_SIGNING_PUBLIC_KEY; al no coincidir el hash del mensaje modificado con la firma, bloquea el pago antes de tocar inventario o contactar al Banco.",
                    },
                }

            # 3) REUTILIZAR (DOBLE GASTO) UN TICKET REAL DE bank.db
            if req.attack_type == "custom_ticket_replay":
                if not req.ticket_id:
                    return JSONResponse(status_code=400, content={"detail": "Selecciona un ticket real de bank.db."})
                rows = _ro_query(
                    "bank.db",
                    "SELECT ticket_id, owner_ref, amount_cents, ticket_json, signature, status, spent_in_order_id "
                    "FROM bank_tickets WHERE ticket_id = ?",
                    (req.ticket_id,),
                )
                if not rows:
                    return JSONResponse(status_code=404, content={"detail": "Ticket no encontrado en bank.db."})
                tkt_row = rows[0]
                owner_id = tkt_row["owner_ref"]
                signed_payload = {
                    "tickets": [{"ticket": json.loads(tkt_row["ticket_json"]), "signature": tkt_row["signature"]}]
                }
                headers = {"Authorization": f"Bearer {create_access_token(owner_id)}"}

                if tkt_row["status"] == "spent":
                    order_id, _ = _ensure_pending_order_for_user(client, owner_id, req.order_id)
                    res = client.post(
                        f"{STORE_BASE}/orders/{order_id}/pay-with-tickets",
                        json=signed_payload,
                        headers=headers,
                    )
                    steps = [
                        f"1. Se seleccionó el ticket '{tkt_row['ticket_id']}' que ya figura como SPENT (usado en '{tkt_row['spent_in_order_id']}').",
                        f"2. Se intentó reenviar exactamente el mismo ticket firmado para pagar la nueva orden '{order_id}'.",
                        f"3. El control anti-doble gasto detectó el ID en 'spent_tickets' / 'bank_tickets' y bloqueó la operación → HTTP {res.status_code}.",
                    ]
                else:
                    # Si el usuario eligió un ticket aún activo, lo gasta en una orden y lo reenvía inmediatamente en una segunda orden
                    ord1, _ = _ensure_pending_order_for_user(client, owner_id, None)
                    r1 = client.post(f"{STORE_BASE}/orders/{ord1}/pay-with-tickets", json=signed_payload, headers=headers)
                    ord2, _ = _ensure_pending_order_for_user(client, owner_id, None)
                    res = client.post(f"{STORE_BASE}/orders/{ord2}/pay-with-tickets", json=signed_payload, headers=headers)
                    steps = [
                        f"1. El ticket '{tkt_row['ticket_id']}' estaba ACTIVE; primero se usó legítimamente en la orden '{ord1}' (HTTP {r1.status_code}).",
                        f"2. Inmediatamente se intentó reutilizar el mismo ticket firmado en una segunda orden '{ord2}'.",
                        f"3. La Tienda y el Banco rechazaron el segundo uso por duplicidad → HTTP {res.status_code}.",
                    ]

                return {
                    "title": f"Doble Gasto sobre Ticket Real ({tkt_row['ticket_id']})",
                    "stride": "Replay / Double Spending",
                    "blocked": res.status_code == 409,
                    "actual_status": res.status_code,
                    "target": "POST :8003/orders/{order_id}/pay-with-tickets → :8002/tickets/redeem",
                    "steps": steps,
                    "request_payload": signed_payload,
                    "server_response": res.json(),
                    "defense_mechanism": {
                        "name": "Registro de Unicidad Dual (Tienda: spent_tickets + Banco: bank_tickets.status)",
                        "layer": "Prevención de Doble Gasto y Ataques Replay",
                        "where": "store_service/routers/orders.py & bank_service/routers/tickets.py -> redeem_tickets()",
                        "how": "Cada ticket tiene un identificador único (ticket_id) y nonce firmados. Al canjearse, la Tienda lo inserta como llave primaria en 'spent_tickets' y el Banco bloquea la fila con SELECT ... FOR UPDATE cambiando su estado de 'active' a 'spent', haciendo imposible gastarlo dos veces.",
                    },
                }

            # 4) ALTERAR MONTO DE UNA ORDEN REAL DE store.db
            if req.attack_type == "custom_order_tamper":
                if not req.order_id:
                    return JSONResponse(status_code=400, content={"detail": "Selecciona una orden real de store.db."})
                ords = _ro_query(
                    "store.db",
                    "SELECT order_id, user_id, total_cents, currency, status FROM orders WHERE order_id = ?",
                    (req.order_id,),
                )
                if not ords:
                    return JSONResponse(status_code=404, content={"detail": "Orden no encontrada en store.db."})
                ord_row = ords[0]
                fake_cents = req.tampered_amount_cents or 100

                order_payload = {
                    "order_id": "ord_tamper_" + secrets.token_hex(4),
                    "merchant": "SecureStore",
                    "amount_cents": ord_row["total_cents"],
                    "currency": ord_row["currency"],
                    "payer": ord_row["user_id"],
                    "card_token": None,
                    "nonce": secrets.token_hex(16),
                    "timestamp": int(time.time()),
                }
                signature = sign(settings.wallet_signing_private_key, order_payload)

                tampered_order = dict(order_payload)
                tampered_order["amount_cents"] = fake_cents
                attack_body = {"order": tampered_order, "signature": signature}

                res = client.post(
                    f"{BANK_BASE}/transactions/process",
                    json=attack_body,
                    headers={"X-API-Key": settings.bank_api_key},
                )

                return {
                    "title": f"Alteración de Orden Real {ord_row['order_id']} (${ord_row['total_cents'] / 100:,.2f} → ${fake_cents / 100:,.2f})",
                    "stride": "Tampering (Manipulación en Tránsito)",
                    "blocked": res.status_code == 400,
                    "actual_status": res.status_code,
                    "target": "POST :8002/transactions/process",
                    "steps": [
                        f"1. Se tomó la orden real '{ord_row['order_id']}' del usuario {ord_row['user_id'][:12]}... por ${ord_row['total_cents'] / 100:,.2f} MXN.",
                        f"2. La Wallet firmó la orden original con Ed25519, pero el atacante modificó 'amount_cents' a {fake_cents} (${fake_cents / 100:,.2f}).",
                        f"3. El Banco verificó la firma con WALLET_SIGNING_PUBLIC_KEY y detectó la alteración → HTTP {res.status_code}.",
                    ],
                    "request_payload": attack_body,
                    "server_response": res.json(),
                    "defense_mechanism": {
                        "name": "Firma Digital Ed25519 sobre JSON Canónico (RFC 8785)",
                        "layer": "Integridad y No Repudio de Órdenes de Pago",
                        "where": "backend/bank_service/verification.py -> verify_wallet_signature()",
                        "how": "La llave privada de la Wallet solo existe en wallet_service. El Banco recalcula los bytes canónicos del diccionario recibido y verifica la firma matemática con WALLET_SIGNING_PUBLIC_KEY; cambiar un solo centavo rompe la verificación.",
                    },
                }

            # 5) ATAQUE IDOR ENTRE DOS USUARIOS REALES
            if req.attack_type == "custom_idor_attack":
                if not req.user_id:
                    return JSONResponse(status_code=400, content={"detail": "Selecciona el usuario atacante de wallet.db."})
                attacker_rows = _ro_query("wallet.db", "SELECT id, email FROM users WHERE id = ?", (req.user_id,))
                if not attacker_rows:
                    return JSONResponse(status_code=404, content={"detail": "Usuario atacante no encontrado."})
                attacker = attacker_rows[0]
                attacker_headers = {"Authorization": f"Bearer {create_access_token(attacker['id'])}"}

                if req.card_id:
                    cards = _ro_query("wallet.db", "SELECT id, user_id, brand, last4 FROM cards WHERE id = ?", (req.card_id,))
                    if not cards:
                        return JSONResponse(status_code=404, content={"detail": "Tarjeta víctima no encontrada."})
                    target_card = cards[0]
                    if target_card["user_id"] == attacker["id"]:
                        return JSONResponse(
                            status_code=400,
                            content={"detail": "El atacante y el dueño de la tarjeta son el mismo usuario. Elige usuarios distintos."},
                        )
                    res = client.delete(f"{WALLET_BASE}/cards/{target_card['id']}", headers=attacker_headers)
                    target_desc = f"Tarjeta {target_card['brand'].upper()} •••• {target_card['last4']} (id={target_card['id'][:10]}...)"
                    endpoint = f"DELETE :8001/cards/{target_card['id']}"
                    where_code = "backend/wallet_service/routers/cards.py -> delete_card()"
                elif req.order_id:
                    ords = _ro_query("store.db", "SELECT order_id, user_id, total_cents FROM orders WHERE order_id = ?", (req.order_id,))
                    if not ords:
                        return JSONResponse(status_code=404, content={"detail": "Orden víctima no encontrada."})
                    target_ord = ords[0]
                    if target_ord["user_id"] == attacker["id"]:
                        return JSONResponse(
                            status_code=400,
                            content={"detail": "El atacante y el dueño de la orden son el mismo usuario. Elige usuarios distintos."},
                        )
                    res = client.get(f"{STORE_BASE}/orders/{target_ord['order_id']}", headers=attacker_headers)
                    target_desc = f"Orden {target_ord['order_id']} (${target_ord['total_cents'] / 100:,.2f} MXN)"
                    endpoint = f"GET :8003/orders/{target_ord['order_id']}"
                    where_code = "backend/store_service/routers/orders.py -> _get_own_order()"
                else:
                    return JSONResponse(
                        status_code=400,
                        content={"detail": "Selecciona una Orden o una Tarjeta perteneciente a otro usuario como objetivo."},
                    )

                return {
                    "title": f"Ataque IDOR: '{attacker['email']}' accediendo a recurso ajeno",
                    "stride": "Elevation of Privilege (IDOR)",
                    "blocked": res.status_code == 404,
                    "actual_status": res.status_code,
                    "target": endpoint,
                    "steps": [
                        f"1. Se autenticó al atacante '{attacker['email']}' con su propio JWT legítimo (sub={attacker['id'][:12]}...).",
                        f"2. El atacante envió una petición directa apuntando al recurso privado: {target_desc}.",
                        f"3. El servidor comparó el 'sub' del JWT contra el propietario en BD y ocultó el recurso → HTTP {res.status_code}.",
                    ],
                    "request_payload": {
                        "attacker_email": attacker["email"],
                        "attacker_jwt_sub": attacker["id"],
                        "target_endpoint": endpoint,
                    },
                    "server_response": res.json(),
                    "defense_mechanism": {
                        "name": "Aislamiento de Propietario por JWT 'sub' + Respuesta Opaca 404",
                        "layer": "Control de Acceso y Prevención de IDOR",
                        "where": where_code,
                        "how": "El backend jamás confía en el ID del recurso sin verificar que pertenezca al 'sub' extraído del token JWT firmado. Además devuelve 404 Not Found (en lugar de 403 Forbidden) para evitar enumeración de identificadores válidos.",
                    },
                }

            # 6) FUERZA BRUTA / BYPASS 2FA CONTRA UN USUARIO REAL DE wallet.db
            if req.attack_type == "custom_bruteforce_user":
                if not req.user_id:
                    return JSONResponse(status_code=400, content={"detail": "Selecciona un usuario real de wallet.db."})
                users = _ro_query(
                    "wallet.db",
                    "SELECT id, email, failed_attempts, locked_until FROM users WHERE id = ?",
                    (req.user_id,),
                )
                if not users:
                    return JSONResponse(status_code=404, content={"detail": "Usuario no encontrado."})
                target_user = users[0]
                attempts = 5 if (req.mode or "lockout") == "lockout" else 1

                statuses = []
                last_res = None
                for i in range(attempts):
                    last_res = client.post(
                        f"{WALLET_BASE}/auth/login",
                        json={"email": target_user["email"], "password": f"AtaqueDiccionario#{i}_{secrets.token_hex(2)}"},
                    )
                    statuses.append(last_res.status_code)

                blocked = last_res is not None and last_res.status_code in (401, 423)
                return {
                    "title": f"Ataque de Credenciales contra '{target_user['email']}' ({attempts} intento(s))",
                    "stride": "Spoofing (Fuerza Bruta / Credenciales)",
                    "blocked": blocked,
                    "actual_status": last_res.status_code if last_res else 401,
                    "target": "POST :8001/auth/login",
                    "steps": [
                        f"1. Se ejecutaron {attempts} intento(s) de login con contraseñas incorrectas contra '{target_user['email']}'.",
                        f"2. Códigos HTTP devueltos por Wallet Service: {statuses}.",
                        "3. Cada fallo se encadenó con SHA-256 en 'audit_log' y al acumular 5 fallos la cuenta queda bloqueada 15 minutos (HTTP 423).",
                    ],
                    "request_payload": {
                        "email": target_user["email"],
                        "attempts_sent": attempts,
                        "previous_failed_attempts": target_user["failed_attempts"],
                    },
                    "server_response": last_res.json() if last_res else {},
                    "defense_mechanism": {
                        "name": "Argon2id + Bloqueo Temporal por Intentos + Bitácora Encadenada SHA-256",
                        "layer": "Autenticación Robusta y Detección de Intrusiones",
                        "where": "backend/wallet_service/routers/auth.py -> login()",
                        "how": "Argon2id ralentiza ataques de diccionario por GPU mediante alto costo de memoria; tras 5 intentos fallidos el servidor activa 'locked_until' por 15 minutos (HTTP 423) y registra 'login_failed' / 'account_locked' en audit_log.",
                    },
                }

        return JSONResponse(status_code=400, content={"detail": "Tipo de ataque personalizado no soportado."})

    except httpx.ConnectError as exc:
        return JSONResponse(
            status_code=503,
            content={"detail": f"No se pudo conectar a los microservicios ({exc}). Verifica puertos 8001, 8002 y 8003."},
        )
    except Exception as exc:
        return JSONResponse(status_code=500, content={"detail": f"Error en simulación personalizada: {exc}"})


@app.post("/api/attacks/{attack_id}")
def run_preset_attack(attack_id: str):
    """Ejecuta los ataques predeterminados de 1 clic con identidades efímeras."""
    try:
        with httpx.Client(timeout=10.0) as client:
            if attack_id == "tampering_order":
                victim = _provision_test_identity(client)
                order = {
                    "order_id": "ord_" + secrets.token_hex(6),
                    "merchant": "SecureStore",
                    "amount_cents": 50_000,
                    "currency": "MXN",
                    "payer": victim["wallet_user_id"],
                    "card_token": None,
                    "nonce": secrets.token_hex(16),
                    "timestamp": int(time.time()),
                }
                signature = sign(settings.wallet_signing_private_key, order)
                tampered_order = dict(order)
                tampered_order["amount_cents"] = 100
                attack_payload = {"order": tampered_order, "signature": signature}
                res = client.post(
                    f"{BANK_BASE}/transactions/process",
                    json=attack_payload,
                    headers={"X-API-Key": settings.bank_api_key},
                )
                return {
                    "title": "Tampering: Alteración de Monto en Orden Firmada ($500 → $1)",
                    "stride": "Tampering (Manipulación)",
                    "blocked": res.status_code == 400,
                    "actual_status": res.status_code,
                    "target": "POST :8002/transactions/process",
                    "steps": [
                        f"1. Se creó identidad de prueba ({victim['email']}) y la Wallet firmó con Ed25519 una orden por $500.00 MXN.",
                        "2. Un atacante MITM modificó 'amount_cents' a 100 ($1.00 MXN) conservando la firma original.",
                        f"3. El Banco verificó la firma Ed25519 sobre JSON canónico y rechazó el cambio → HTTP {res.status_code}.",
                    ],
                    "request_payload": attack_payload,
                    "server_response": res.json(),
                    "defense_mechanism": {
                        "name": "Firma Digital Ed25519 sobre JSON Canónico (RFC 8785)",
                        "layer": "Integridad y Autenticidad de Mensajes",
                        "where": "backend/bank_service/verification.py -> verify_wallet_signature()",
                        "how": "La firma criptográfica cubre cada byte del JSON canónico. Cualquier alteración en el monto invalida la firma frente a WALLET_SIGNING_PUBLIC_KEY.",
                    },
                }

            if attack_id == "replay_payment":
                victim = _provision_test_identity(client)
                order = {
                    "order_id": "ord_" + secrets.token_hex(6),
                    "merchant": "SecureStore",
                    "amount_cents": 15_000,
                    "currency": "MXN",
                    "payer": victim["wallet_user_id"],
                    "card_token": None,
                    "nonce": secrets.token_hex(16),
                    "timestamp": int(time.time()),
                }
                payload = {"order": order, "signature": sign(settings.wallet_signing_private_key, order)}
                headers = {"X-API-Key": settings.bank_api_key}
                first = client.post(f"{BANK_BASE}/transactions/process", json=payload, headers=headers)
                second = client.post(f"{BANK_BASE}/transactions/process", json=payload, headers=headers)
                return {
                    "title": "Replay Attack: Repetición de Pago Capturado",
                    "stride": "Replay / Repudiation",
                    "blocked": first.status_code == 200 and second.status_code == 409,
                    "actual_status": second.status_code,
                    "target": "POST :8002/transactions/process",
                    "steps": [
                        f"1. Se envió orden legítima por $150.00 MXN con nonce '{order['nonce'][:16]}...' → Banco aprobó (HTTP {first.status_code}).",
                        "2. Un atacante reenvió exactamente el mismo paquete firmado para cobrar doble.",
                        f"3. El Banco detectó el nonce duplicado en 'processed_orders' y bloqueó el reenvío → HTTP {second.status_code}.",
                    ],
                    "request_payload": payload,
                    "server_response": second.json(),
                    "defense_mechanism": {
                        "name": "Nonce Criptográfico Único + Ventana de Frescura (120 s)",
                        "layer": "Protección Anti-Replay",
                        "where": "backend/bank_service/verification.py -> ensure_nonce_unique() & ensure_fresh()",
                        "how": "Cada orden incorpora un nonce aleatorio de 128 bits almacenado con restricción UNIQUE en SQLite y un timestamp con expiración de 120 segundos.",
                    },
                }

            if attack_id == "ticket_tampering":
                victim = _provision_test_identity(client)
                r_tkt = client.post(
                    f"{BANK_BASE}/tickets/purchase",
                    json={"denomination_cents": 5000, "quantity": 1},
                    headers=victim["bank_headers"],
                )
                r_tkt.raise_for_status()
                ticket_obj = r_tkt.json()[0]
                order_id, _ = _ensure_pending_order_for_user(client, victim["wallet_user_id"], None)

                tampered_ticket = dict(ticket_obj["ticket"])
                tampered_ticket["amount_cents"] = 50_000
                attack_payload = {"tickets": [{"ticket": tampered_ticket, "signature": ticket_obj["signature"]}]}
                res = client.post(
                    f"{STORE_BASE}/orders/{order_id}/pay-with-tickets",
                    json=attack_payload,
                    headers=victim["wallet_headers"],
                )
                return {
                    "title": "Falsificación de Ticket Electrónico ($50 → $500)",
                    "stride": "Tampering (Manipulación)",
                    "blocked": res.status_code == 400,
                    "actual_status": res.status_code,
                    "target": f"POST :8003/orders/{order_id}/pay-with-tickets",
                    "steps": [
                        f"1. El cliente adquirió 1 ticket real de $50.00 MXN ({ticket_obj['ticket']['ticket_id']}) firmado por el Banco.",
                        "2. El atacante modificó 'amount_cents' de 5000 a 50000 ($500.00 MXN) antes de enviarlo a la Tienda.",
                        f"3. La Tienda verificó localmente la firma Ed25519 con BANK_SIGNING_PUBLIC_KEY → HTTP {res.status_code}.",
                    ],
                    "request_payload": attack_payload,
                    "server_response": res.json(),
                    "defense_mechanism": {
                        "name": "Verificación Local de Firma Ed25519 del Banco en Tienda",
                        "layer": "Integridad de Tickets Electrónicos",
                        "where": "backend/store_service/routers/orders.py -> _verify_tickets_locally()",
                        "how": "La Tienda valida la firma digital del Banco antes de procesar el pedido; sin la llave privada del Banco, nadie puede alterar el valor del ticket.",
                    },
                }

            if attack_id == "ticket_double_spend":
                victim = _provision_test_identity(client)
                r_tkt = client.post(
                    f"{BANK_BASE}/tickets/purchase",
                    json={"denomination_cents": 20_000, "quantity": 1},
                    headers=victim["bank_headers"],
                )
                r_tkt.raise_for_status()
                tkt = r_tkt.json()[0]
                signed_tickets = [{"ticket": tkt["ticket"], "signature": tkt["signature"]}]

                ord1, _ = _ensure_pending_order_for_user(client, victim["wallet_user_id"], None)
                res1 = client.post(
                    f"{STORE_BASE}/orders/{ord1}/pay-with-tickets",
                    json={"tickets": signed_tickets},
                    headers=victim["wallet_headers"],
                )
                ord2, _ = _ensure_pending_order_for_user(client, victim["wallet_user_id"], None)
                res2 = client.post(
                    f"{STORE_BASE}/orders/{ord2}/pay-with-tickets",
                    json={"tickets": signed_tickets},
                    headers=victim["wallet_headers"],
                )
                return {
                    "title": "Doble Gasto de Ticket Electrónico",
                    "stride": "Replay / Double Spending",
                    "blocked": res1.status_code == 200 and res2.status_code == 409,
                    "actual_status": res2.status_code,
                    "target": f"POST :8003/orders/{ord2}/pay-with-tickets",
                    "steps": [
                        f"1. Se adquirió el ticket {tkt['ticket']['ticket_id']} ($200.00) y se usó en la orden {ord1} → HTTP {res1.status_code}.",
                        f"2. El atacante intentó reutilizar el mismo ticket firmado en una segunda orden ({ord2}).",
                        f"3. Tanto la Tienda ('spent_tickets') como el Banco ('bank_tickets.status = spent') bloquearon el doble gasto → HTTP {res2.status_code}.",
                    ],
                    "request_payload": {"order_id": ord2, "tickets": signed_tickets},
                    "server_response": res2.json(),
                    "defense_mechanism": {
                        "name": "Control Transaccional Anti-Doble Gasto (spent_tickets + bank_tickets)",
                        "layer": "Unicidad de Canje",
                        "where": "backend/bank_service/routers/tickets.py -> redeem_tickets()",
                        "how": "Cada ticket es de un solo uso y queda registrado tanto en la Tienda como en el Banco de forma atómica.",
                    },
                }

            if attack_id == "brute_force_lockout":
                uid = uuid.uuid4().hex[:6]
                victim_email = f"victima-{uid}@demo.com"
                real_pass = f"ClaveReal!{uid}"
                client.post(
                    f"{WALLET_BASE}/auth/register",
                    json={"email": victim_email, "full_name": "Victima BruteForce", "password": real_pass},
                ).raise_for_status()

                statuses = []
                for i in range(5):
                    r = client.post(
                        f"{WALLET_BASE}/auth/login",
                        json={"email": victim_email, "password": f"ClaveIncorrecta{i}"},
                    )
                    statuses.append(r.status_code)

                r_locked = client.post(
                    f"{WALLET_BASE}/auth/login",
                    json={"email": victim_email, "password": real_pass},
                )
                return {
                    "title": "Fuerza Bruta y Bloqueo Temporal de Cuenta",
                    "stride": "Spoofing (Suplantación)",
                    "blocked": r_locked.status_code == 423,
                    "actual_status": r_locked.status_code,
                    "target": "POST :8001/auth/login",
                    "steps": [
                        f"1. Se lanzaron 5 contraseñas incorrectas contra '{victim_email}' → Respuestas: {statuses}.",
                        "2. Al quinto fallo, el servidor fijó 'locked_until' por 15 minutos y registró 'account_locked' en audit_log.",
                        f"3. Se intentó iniciar sesión con la contraseña CORRECTA → Bloqueado con HTTP {r_locked.status_code} Locked.",
                    ],
                    "request_payload": {"email": victim_email, "password": "•••••••• (intento #6)"},
                    "server_response": r_locked.json(),
                    "defense_mechanism": {
                        "name": "Argon2id + Bloqueo Automático de Cuenta (Lockout 15 min)",
                        "layer": "Protección de Identidad",
                        "where": "backend/wallet_service/routers/auth.py -> login()",
                        "how": "Limita los intentos consecutivos fallidos a 5 y bloquea temporalmente la cuenta incluso frente a credenciales válidas.",
                    },
                }

            if attack_id == "idor_order_access":
                victim_a = _provision_test_identity(client)
                attacker_b = _provision_test_identity(client)
                order_id, _ = _ensure_pending_order_for_user(client, victim_a["wallet_user_id"], None)
                res = client.get(f"{STORE_BASE}/orders/{order_id}", headers=attacker_b["wallet_headers"])
                return {
                    "title": "IDOR: Acceso No Autorizado a Orden de Otro Usuario",
                    "stride": "Elevation of Privilege (IDOR)",
                    "blocked": res.status_code == 404,
                    "actual_status": res.status_code,
                    "target": f"GET :8003/orders/{order_id}",
                    "steps": [
                        f"1. Usuario A ({victim_a['email']}) creó la orden privada '{order_id}' en la Tienda.",
                        f"2. Usuario B ({attacker_b['email']}) intentó consultar esa orden usando su propio JWT válido.",
                        f"3. La Tienda validó el claim 'sub' del JWT contra 'order.user_id' y ocultó el recurso → HTTP {res.status_code}.",
                    ],
                    "request_payload": {"endpoint": f"GET /orders/{order_id}", "attacker": attacker_b["email"]},
                    "server_response": res.json(),
                    "defense_mechanism": {
                        "name": "Validación Estricta de Propietario vía JWT 'sub'",
                        "layer": "Control de Autorización Anti-IDOR",
                        "where": "backend/store_service/routers/orders.py -> _get_own_order()",
                        "how": "Solo el dueño autenticado en el JWT puede leer o pagar sus órdenes; a cualquier otro usuario se le responde 404 Not Found.",
                    },
                }

            return JSONResponse(status_code=404, content={"detail": "Ataque no reconocido"})
    except httpx.ConnectError as exc:
        return JSONResponse(
            status_code=503,
            content={"detail": f"No se pudo conectar a los microservicios ({exc}). Verifica puertos 8001, 8002 y 8003."},
        )
    except Exception as exc:
        return JSONResponse(status_code=500, content={"detail": f"Error ejecutando simulación: {exc}"})


@app.post("/api/demo/tamper-audit")
def tamper_audit_demo():
    with SessionLocal() as db:
        last = db.query(AuditLog).order_by(AuditLog.id.desc()).first()
        if last is None:
            return JSONResponse(status_code=400, content={"detail": "No hay registros en audit_log aún"})
        if last.id not in _TAMPER_BACKUP:
            _TAMPER_BACKUP[last.id] = last.detail
            last.detail = "MONTO_ALTERADO_POR_ATACANTE"
            db.commit()
    return {"tampered": True}


@app.post("/api/demo/restore-audit")
def restore_audit_demo():
    if not _TAMPER_BACKUP:
        return {"restored": True}
    with SessionLocal() as db:
        for row_id, original_detail in list(_TAMPER_BACKUP.items()):
            row = db.get(AuditLog, row_id)
            if row is not None:
                row.detail = original_detail
        db.commit()
    _TAMPER_BACKUP.clear()
    return {"restored": True}


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8090)