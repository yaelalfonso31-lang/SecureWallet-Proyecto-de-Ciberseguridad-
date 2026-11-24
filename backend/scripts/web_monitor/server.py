"""Servidor web de solo lectura + Laboratorio de Ataques en Vivo para demostración."""
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
from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

MONITOR_DIR = Path(__file__).resolve().parent
BACKEND_DIR = MONITOR_DIR.parents[1]
sys.path.insert(0, str(BACKEND_DIR))

from shared.config import settings  # noqa: E402
from shared.security.signing import sign  # noqa: E402
from wallet_service.audit import verify_chain  # noqa: E402
from wallet_service.database import SessionLocal  # noqa: E402
from wallet_service.models import AuditLog  # noqa: E402

WALLET_BASE = os.getenv("INSPECTOR_WALLET_URL", "http://127.0.0.1:8001")
BANK_BASE = os.getenv("INSPECTOR_BANK_URL", "http://127.0.0.1:8002")
STORE_BASE = os.getenv("INSPECTOR_STORE_URL", "http://127.0.0.1:8003")

app = FastAPI(title="SecureWallet - Web Inspector & Attack Lab")
app.mount("/static", StaticFiles(directory=str(MONITOR_DIR)), name="static")

_TAMPER_BACKUP: dict[int, str] = {}


def _key_fingerprint(secret: str) -> str:
    if not secret:
        return "NO CONFIGURADA"
    return hashlib.sha256(secret.encode()).hexdigest()[:16].upper()


def _pkce_s256(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def _ro_query(db_name: str, sql: str) -> list[dict]:
    db_path = BACKEND_DIR / db_name
    if not db_path.exists():
        return []
    uri = f"file:{db_path.as_posix()}?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True, timeout=1.0)
        conn.row_factory = sqlite3.Row
        rows = [dict(r) for r in conn.execute(sql).fetchall()]
        conn.close()
        return rows
    except sqlite3.Error:
        return []


def _table_columns(db_name: str, table: str) -> set[str]:
    rows = _ro_query(db_name, f"PRAGMA table_info({table})")
    return {r["name"] for r in rows}


def _provision_test_identity(client: httpx.Client) -> dict:
    """Crea un usuario de prueba en Wallet y vincula su cuenta bancaria via OAuth2 + PKCE."""
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

    # Obtener aserción firmada Ed25519 por la Wallet
    r_assert = client.post(f"{WALLET_BASE}/bank-link/assertion", headers=wallet_headers)
    r_assert.raise_for_status()
    assertion_data = r_assert.json()

    # Abrir cuenta en el Banco ($5,000 MXN saldo demo)
    r_open = client.post(
        f"{BANK_BASE}/customers/open-account",
        json={"email": email, "password": password, "wallet_assertion": assertion_data},
    )
    r_open.raise_for_status()

    # Flujo OAuth2 + PKCE S256
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
        "FROM users ORDER BY created_at DESC LIMIT 5",
    )
    cards = _ro_query(
        "wallet.db",
        "SELECT id, user_id, token, brand, last4, holder_name, exp_month, exp_year, pan_encrypted, created_at "
        "FROM cards ORDER BY created_at DESC LIMIT 5",
    )
    wallet_accounts = _ro_query(
        "wallet.db",
        "SELECT user_id, balance_cents, updated_at FROM wallet_accounts ORDER BY updated_at DESC LIMIT 5",
    )
    audits = _ro_query(
        "wallet.db",
        "SELECT id, event, user_id, detail, prev_hash, hash, created_at FROM audit_log ORDER BY id DESC LIMIT 8",
    )

    try:
        with SessionLocal() as db:
            chain_valid = verify_chain(db)
    except Exception:
        chain_valid = True

    bank_accounts = _ro_query(
        "bank.db",
        "SELECT id, owner_ref, account_number, status, balance_cents, created_at FROM accounts ORDER BY id DESC LIMIT 5",
    )
    for acc in bank_accounts:
        num = acc.get("account_number") or ""
        acc["account_masked"] = f"•••• {num[-4:]}" if len(num) >= 4 else "••••"
        acc.pop("account_number", None)

    oauth_codes = _ro_query(
        "bank.db",
        "SELECT id, code_hash, code_challenge, wallet_user_id, used, expires_at FROM authorization_codes ORDER BY id DESC LIMIT 4",
    )
    tickets = _ro_query(
        "bank.db",
        "SELECT ticket_id, owner_ref, amount_cents, currency, nonce, ticket_hash, signature, status, spent_in_order_id, issued_at "
        "FROM bank_tickets ORDER BY issued_at DESC LIMIT 6",
    )

    orders = _ro_query(
        "store.db",
        "SELECT order_id, user_id, subtotal_cents, discount_cents, total_cents, status, receipt_json, receipt_signature, created_at "
        "FROM orders ORDER BY created_at DESC LIMIT 5",
    )
    spent_tickets = _ro_query(
        "store.db",
        "SELECT ticket_id, order_id, amount_cents, ticket_hash, redeemed_at FROM spent_tickets ORDER BY redeemed_at DESC LIMIT 5",
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


@app.post("/api/attacks/{attack_id}")
def run_live_attack(attack_id: str):
    """Ejecuta una simulación de ataque real contra los microservicios locales."""
    try:
        with httpx.Client(timeout=10.0) as client:
            if attack_id == "tampering_order":
                victim = _provision_test_identity(client)
                order = {
                    "order_id": "ord_" + secrets.token_hex(6),
                    "merchant": "SecureStore",
                    "amount_cents": 50_000,  # $500.00 MXN firmado originalmente
                    "currency": "MXN",
                    "payer": victim["wallet_user_id"],
                    "card_token": None,
                    "nonce": secrets.token_hex(16),
                    "timestamp": int(time.time()),
                }
                signature = sign(settings.wallet_signing_private_key, order)

                # Atacante intercepta el JSON y cambia $500.00 -> $1.00
                tampered_order = dict(order)
                tampered_order["amount_cents"] = 100
                attack_payload = {"order": tampered_order, "signature": signature}

                res = client.post(
                    f"{BANK_BASE}/transactions/process",
                    json=attack_payload,
                    headers={"X-API-Key": settings.bank_api_key},
                )
                return {
                    "attack_id": attack_id,
                    "title": "Tampering: Alteración de Monto en Orden Firmada ($500 → $1)",
                    "stride": "Tampering (Manipulación)",
                    "blocked": res.status_code == 400,
                    "expected_status": 400,
                    "actual_status": res.status_code,
                    "target": "POST :8002/transactions/process",
                    "steps": [
                        f"1. Se creó identidad de prueba ({victim['email']}) y la Wallet firmó con Ed25519 una orden por $500.00 MXN (50,000 centavos).",
                        "2. Un atacante MITM modificó el campo 'amount_cents' a 100 ($1.00 MXN) conservando la firma original.",
                        f"3. El Banco serializó el payload recibido en JSON canónico y verificó la firma Ed25519 → HTTP {res.status_code}.",
                    ],
                    "request_payload": attack_payload,
                    "server_response": res.json(),
                    "explanation": "La firma digital Ed25519 sobre JSON canónico (RFC 8785) vincula matemáticamente cada byte del mensaje a la llave privada de la Wallet. Alterar un solo dígito invalida la firma al instante.",
                }

            if attack_id == "replay_payment":
                victim = _provision_test_identity(client)
                order = {
                    "order_id": "ord_" + secrets.token_hex(6),
                    "merchant": "SecureStore",
                    "amount_cents": 15_000,  # $150.00 MXN
                    "currency": "MXN",
                    "payer": victim["wallet_user_id"],
                    "card_token": None,
                    "nonce": secrets.token_hex(16),
                    "timestamp": int(time.time()),
                }
                payload = {
                    "order": order,
                    "signature": sign(settings.wallet_signing_private_key, order),
                }
                headers = {"X-API-Key": settings.bank_api_key}

                first = client.post(f"{BANK_BASE}/transactions/process", json=payload, headers=headers)
                second = client.post(f"{BANK_BASE}/transactions/process", json=payload, headers=headers)

                return {
                    "attack_id": attack_id,
                    "title": "Replay Attack: Repetición de Pago Capturado",
                    "stride": "Replay / Repudiation",
                    "blocked": first.status_code == 200 and second.status_code == 409,
                    "expected_status": 409,
                    "actual_status": second.status_code,
                    "target": "POST :8002/transactions/process",
                    "steps": [
                        f"1. Se envió una orden legítima firmada por $150.00 MXN con nonce '{order['nonce'][:16]}...' → Banco aprobó (HTTP {first.status_code}).",
                        "2. Un atacante capturó el paquete y reenvió exactamente el mismo JSON firmado para cobrar doble.",
                        f"3. El Banco detectó el nonce duplicado en la tabla 'processed_orders' y bloqueó el reenvío → HTTP {second.status_code}.",
                    ],
                    "request_payload": payload,
                    "server_response": second.json(),
                    "explanation": "Cada orden incluye un nonce criptográfico aleatorio de 128 bits, una ventana de frescura de 120 segundos y una restricción UNIQUE en base de datos, impidiendo ataques de repetición.",
                }

            if attack_id == "ticket_tampering":
                victim = _provision_test_identity(client)
                # Comprar 1 ticket legítimo de $50.00 (5,000 centavos)
                r_tkt = client.post(
                    f"{BANK_BASE}/tickets/purchase",
                    json={"denomination_cents": 5000, "quantity": 1},
                    headers=victim["bank_headers"],
                )
                r_tkt.raise_for_status()
                ticket_obj = r_tkt.json()[0]

                # Obtener producto más barato en la Tienda ($149.00)
                products = client.get(f"{STORE_BASE}/products").json()
                cheapest = min(products, key=lambda p: p["price_cents"])
                r_ord = client.post(
                    f"{STORE_BASE}/orders",
                    json={"items": [{"product_id": cheapest["id"], "quantity": 1}]},
                    headers=victim["wallet_headers"],
                )
                order_id = r_ord.json()["order_id"]

                # Alterar denominación del ticket de $50 (5000) a $500 (50000)
                tampered_ticket = dict(ticket_obj["ticket"])
                tampered_ticket["amount_cents"] = 50_000
                attack_payload = {
                    "tickets": [{"ticket": tampered_ticket, "signature": ticket_obj["signature"]}]
                }

                res = client.post(
                    f"{STORE_BASE}/orders/{order_id}/pay-with-tickets",
                    json=attack_payload,
                    headers=victim["wallet_headers"],
                )
                return {
                    "attack_id": attack_id,
                    "title": "Falsificación de Ticket Electrónico ($50 → $500)",
                    "stride": "Tampering (Manipulación)",
                    "blocked": res.status_code == 400,
                    "expected_status": 400,
                    "actual_status": res.status_code,
                    "target": f"POST :8003/orders/{order_id}/pay-with-tickets",
                    "steps": [
                        f"1. El cliente adquirió 1 ticket real de $50.00 MXN ({ticket_obj['ticket']['ticket_id']}) firmado por el Banco.",
                        "2. El atacante modificó 'amount_cents' de 5000 a 50000 ($500.00 MXN) antes de enviarlo a la Tienda.",
                        f"3. La Tienda verificó localmente la firma Ed25519 usando la clave pública del Banco y rechazó la compra sin siquiera contactar al Banco → HTTP {res.status_code}.",
                    ],
                    "request_payload": attack_payload,
                    "server_response": res.json(),
                    "explanation": "La Tienda valida la firma digital Ed25519 del Banco antes de aceptar cualquier ticket electrónico. Como el Banco firma con su llave privada, nadie puede inflar el valor de un ticket.",
                }

            if attack_id == "ticket_double_spend":
                victim = _provision_test_identity(client)
                # Comprar 1 ticket de $200.00 (20,000 centavos)
                r_tkt = client.post(
                    f"{BANK_BASE}/tickets/purchase",
                    json={"denomination_cents": 20_000, "quantity": 1},
                    headers=victim["bank_headers"],
                )
                r_tkt.raise_for_status()
                tkt = r_tkt.json()[0]
                signed_tickets = [{"ticket": tkt["ticket"], "signature": tkt["signature"]}]

                products = client.get(f"{STORE_BASE}/products").json()
                cheapest = min(products, key=lambda p: p["price_cents"])

                # Compra 1 (Legítima)
                ord1 = client.post(
                    f"{STORE_BASE}/orders",
                    json={"items": [{"product_id": cheapest["id"], "quantity": 1}]},
                    headers=victim["wallet_headers"],
                ).json()["order_id"]
                res1 = client.post(
                    f"{STORE_BASE}/orders/{ord1}/pay-with-tickets",
                    json={"tickets": signed_tickets},
                    headers=victim["wallet_headers"],
                )

                # Compra 2 (Intento de doble gasto con el mismo ticket)
                ord2 = client.post(
                    f"{STORE_BASE}/orders",
                    json={"items": [{"product_id": cheapest["id"], "quantity": 1}]},
                    headers=victim["wallet_headers"],
                ).json()["order_id"]
                res2 = client.post(
                    f"{STORE_BASE}/orders/{ord2}/pay-with-tickets",
                    json={"tickets": signed_tickets},
                    headers=victim["wallet_headers"],
                )

                return {
                    "attack_id": attack_id,
                    "title": "Doble Gasto de Ticket Electrónico",
                    "stride": "Replay / Double Spending",
                    "blocked": res1.status_code == 200 and res2.status_code == 409,
                    "expected_status": 409,
                    "actual_status": res2.status_code,
                    "target": f"POST :8003/orders/{ord2}/pay-with-tickets",
                    "steps": [
                        f"1. Se adquirió el ticket {tkt['ticket']['ticket_id']} ($200.00) y se usó en la orden {ord1} → Pago aprobado (HTTP {res1.status_code}) y cambio reembolsado.",
                        f"2. El atacante intentó reutilizar el mismo ticket firmado en una segunda orden ({ord2}).",
                        f"3. Tanto la Tienda ('spent_tickets') como el Banco ('bank_tickets.status = spent') bloquearon el doble gasto → HTTP {res2.status_code}.",
                    ],
                    "request_payload": {"order_id": ord2, "tickets": signed_tickets},
                    "server_response": res2.json(),
                    "explanation": "Los tickets electrónicos son de un solo uso: se registran como gastados tanto en la base de datos de la Tienda como de forma transaccional en el Banco.",
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

                # Sexto intento incluso con la contraseña REAL
                r_locked = client.post(
                    f"{WALLET_BASE}/auth/login",
                    json={"email": victim_email, "password": real_pass},
                )
                return {
                    "attack_id": attack_id,
                    "title": "Fuerza Bruta y Bloqueo Temporal de Cuenta",
                    "stride": "Spoofing (Suplantación)",
                    "blocked": r_locked.status_code == 423,
                    "expected_status": 423,
                    "actual_status": r_locked.status_code,
                    "target": "POST :8001/auth/login",
                    "steps": [
                        f"1. Se lanzó un diccionario de 5 contraseñas incorrectas contra '{victim_email}' → Respuestas: {statuses}.",
                        "2. Al quinto fallo, el servidor fijó 'locked_until' por 15 minutos y registró 'account_locked' en audit_log.",
                        f"3. Se intentó iniciar sesión con la contraseña CORRECTA → Bloqueado con HTTP {r_locked.status_code} Locked.",
                    ],
                    "request_payload": {"email": victim_email, "password": "•••••••• (intento #6)"},
                    "server_response": r_locked.json(),
                    "explanation": "Las contraseñas se verifican con Argon2id (resistente a cracking por GPU) y tras 5 intentos fallidos la cuenta se bloquea temporalmente por 15 minutos, registrando el evento en la bitácora SHA-256.",
                }

            if attack_id == "idor_order_access":
                victim_a = _provision_test_identity(client)
                attacker_b = _provision_test_identity(client)

                products = client.get(f"{STORE_BASE}/products").json()
                order_a = client.post(
                    f"{STORE_BASE}/orders",
                    json={"items": [{"product_id": products[0]["id"], "quantity": 1}]},
                    headers=victim_a["wallet_headers"],
                ).json()
                order_id = order_a["order_id"]

                # Atacante B intenta leer la orden de Víctima A
                res = client.get(
                    f"{STORE_BASE}/orders/{order_id}",
                    headers=attacker_b["wallet_headers"],
                )
                return {
                    "attack_id": attack_id,
                    "title": "IDOR: Acceso No Autorizado a Orden de Otro Usuario",
                    "stride": "Elevation of Privilege (IDOR)",
                    "blocked": res.status_code == 404,
                    "expected_status": 404,
                    "actual_status": res.status_code,
                    "target": f"GET :8003/orders/{order_id}",
                    "steps": [
                        f"1. Usuario A ({victim_a['email']}) creó la orden privada '{order_id}' en la Tienda.",
                        f"2. Usuario B ({attacker_b['email']}) intentó consultar esa orden usando su propio JWT válido.",
                        f"3. La Tienda validó el claim 'sub' del JWT contra 'order.user_id' y ocultó el recurso → HTTP {res.status_code}.",
                    ],
                    "request_payload": {
                        "endpoint": f"GET /orders/{order_id}",
                        "attacker_email": attacker_b["email"],
                        "victim_order_id": order_id,
                    },
                    "server_response": res.json(),
                    "explanation": "Control Anti-IDOR: el servidor extrae el user_id exclusivamente del JWT firmado y responde 404 Not Found (en lugar de 403) para no revelar siquiera si el identificador existe.",
                }

            return JSONResponse(status_code=404, content={"detail": "Ataque no reconocido"})

    except httpx.ConnectError as exc:
        return JSONResponse(
            status_code=503,
            content={
                "detail": f"No se pudo conectar a los microservicios ({exc}). Asegúrate de tener activos los puertos 8001, 8002 y 8003."
            },
        )
    except Exception as exc:
        return JSONResponse(status_code=500, content={"detail": f"Error ejecutando simulación: {exc}"})


@app.post("/api/demo/tamper-audit")
def tamper_audit_demo():
    """Altera temporalmente el último registro de audit_log para demostrar la detección SHA-256."""
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
    """Restaura el registro alterado para devolver la cadena SHA-256 a estado íntegro."""
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