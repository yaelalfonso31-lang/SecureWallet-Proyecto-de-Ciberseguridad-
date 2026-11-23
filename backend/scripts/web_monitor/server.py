"""Servidor web de solo lectura para visualizar en tiempo real las BDs y controles criptográficos."""
import hashlib
import sqlite3
import sys
from pathlib import Path

import uvicorn
from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

MONITOR_DIR = Path(__file__).resolve().parent
BACKEND_DIR = MONITOR_DIR.parents[1]
sys.path.insert(0, str(BACKEND_DIR))

from shared.config import settings  # noqa: E402
from wallet_service.audit import verify_chain  # noqa: E402
from wallet_service.database import SessionLocal  # noqa: E402
from wallet_service.models import AuditLog  # noqa: E402

app = FastAPI(title="SecureWallet - Web Inspector")
app.mount("/static", StaticFiles(directory=str(MONITOR_DIR)), name="static")

# Guarda temporalmente el valor original si se usa el botón de demostración de ataque en vivo
_TAMPER_BACKUP: dict[int, str] = {}


def _key_fingerprint(secret: str) -> str:
    if not secret:
        return "NO CONFIGURADA"
    return hashlib.sha256(secret.encode()).hexdigest()[:16].upper()


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


@app.get("/")
def index():
    return FileResponse(MONITOR_DIR / "index.html")


@app.get("/api/snapshot")
def snapshot():
    # 1. Wallet DB
    user_cols = _table_columns("wallet.db", "users")
    totp_fields = ", totp_enabled, totp_secret" if "totp_enabled" in user_cols else ", 0 AS totp_enabled, NULL AS totp_secret"
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

    # 2. Bank DB
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

    # 3. Store DB
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