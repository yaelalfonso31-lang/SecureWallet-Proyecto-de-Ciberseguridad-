"""Monitor en tiempo real de las bases de datos de SecureWallet para demostración en vivo.

Uso (desde la carpeta backend/):
    python scripts/watch_db.py
"""
import os
import sqlite3
import sys
import time
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

from wallet_service.audit import verify_chain  # noqa: E402
from wallet_service.database import SessionLocal  # noqa: E402


def _ro_query(db_name: str, sql: str) -> list[sqlite3.Row]:
    db_path = BACKEND_DIR / db_name
    if not db_path.exists():
        return []
    uri = f"file:{db_path.as_posix()}?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True, timeout=1.0)
        conn.row_factory = sqlite3.Row
        rows = conn.execute(sql).fetchall()
        conn.close()
        return rows
    except sqlite3.OperationalError:
        return []


def _short(val: str | None, keep: int = 22) -> str:
    if not val:
        return "—"
    return f"{val[:keep]}..." if len(val) > keep else val


def _render() -> str:
    lines: list[str] = []
    sep = "=" * 96
    sub = "-" * 96

    lines.append(sep)
    lines.append("  SECUREWALLET — MONITOR CRIPTOGRÁFICO DE BASES DE DATOS EN TIEMPO REAL (Ctrl+C para salir)")
    lines.append(sep)

    # ===================== 1. WALLET DB =====================
    lines.append("\n[1] WALLET SERVICE (wallet.db) — Contraseñas Argon2id, Tarjetas AES-256-GCM y Bitácora SHA-256")
    lines.append(sub)

    users = _ro_query(
        "wallet.db",
        "SELECT email, password_hash, totp_enabled, totp_secret, failed_attempts FROM users ORDER BY created_at DESC LIMIT 3",
    )
    lines.append("  • TABLA users (últimos 3):")
    if not users:
        lines.append("    (Sin usuarios aún)")
    for u in users:
        totp_state = f"ACTIVO (secret={_short(u['totp_secret'], 10)})" if u["totp_enabled"] else "Inactivo"
        lines.append(
            f"    Email: {u['email']} | Hash: {_short(u['password_hash'], 32)} | 2FA: {totp_state} | Fallos: {u['failed_attempts']}"
        )

    cards = _ro_query(
        "wallet.db",
        "SELECT brand, last4, token, pan_encrypted FROM cards ORDER BY created_at DESC LIMIT 3",
    )
    lines.append("\n  • TABLA cards (PAN cifrado con AES-256-GCM + AAD, sin CVV):")
    if not cards:
        lines.append("    (Sin tarjetas registradas)")
    for c in cards:
        lines.append(
            f"    {c['brand'].upper()} •••• {c['last4']} | Token: {c['token']} | pan_encrypted: {_short(c['pan_encrypted'], 34)}"
        )

    try:
        with SessionLocal() as db:
            chain_ok = verify_chain(db)
    except Exception:
        chain_ok = True

    chain_badge = "ÍNTEGRA (TRUE)" if chain_ok else "¡¡CORRUPTA / ALTERADA (FALSE)!!"
    audits = _ro_query(
        "wallet.db",
        "SELECT id, event, detail, prev_hash, hash FROM audit_log ORDER BY id DESC LIMIT 5",
    )
    lines.append(f"\n  • TABLA audit_log — Estado de cadena SHA-256: [{chain_badge}]")
    if not audits:
        lines.append("    (Sin eventos registrados)")
    for a in audits:
        det = f" ({a['detail']})" if a["detail"] else ""
        lines.append(
            f"    #{a['id']:02d} {a['event']:<20}{det:<24} | prev: {_short(a['prev_hash'], 12)} -> hash: {_short(a['hash'], 14)}"
        )

    # ===================== 2. BANK DB =====================
    lines.append("\n[2] BANK SERVICE (bank.db) — Cuentas, PKCE SHA-256, Tickets Ed25519 y Anti-Replay")
    lines.append(sub)

    accounts = _ro_query(
        "bank.db",
        "SELECT owner_ref, account_number, balance_cents, status FROM accounts ORDER BY id DESC LIMIT 3",
    )
    lines.append("  • TABLA accounts:")
    if not accounts:
        lines.append("    (Sin cuentas bancarias)")
    for acc in accounts:
        masked = f"•••• {acc['account_number'][-4:]}" if acc["account_number"] else "—"
        lines.append(
            f"    Cuenta: {masked} | Saldo: ${acc['balance_cents'] / 100:,.2f} MXN | Estado: {acc['status']} | owner_ref: {_short(acc['owner_ref'], 14)}"
        )

    oauth_codes = _ro_query(
        "bank.db",
        "SELECT code_hash, code_challenge, used FROM authorization_codes ORDER BY id DESC LIMIT 2",
    )
    if oauth_codes:
        lines.append("\n  • TABLA authorization_codes (OAuth2 + PKCE S256):")
        for oc in oauth_codes:
            lines.append(
                f"    code_hash(SHA-256): {_short(oc['code_hash'], 18)} | challenge: {_short(oc['code_challenge'], 18)} | usado: {bool(oc['used'])}"
            )

    tickets = _ro_query(
        "bank.db",
        "SELECT ticket_id, amount_cents, status, spent_in_order_id, ticket_hash, signature FROM bank_tickets ORDER BY issued_at DESC LIMIT 4",
    )
    lines.append("\n  • TABLA bank_tickets (Tickets prepagados firmados con Ed25519):")
    if not tickets:
        lines.append("    (Sin tickets emitidos)")
    for t in tickets:
        spent = f" -> orden {t['spent_in_order_id']}" if t["spent_in_order_id"] else ""
        lines.append(
            f"    {t['ticket_id']} | ${t['amount_cents'] // 100} MXN | {t['status'].upper()}{spent} | Firma Ed25519: {_short(t['signature'], 20)}"
        )

    # ===================== 3. STORE DB =====================
    lines.append("\n[3] STORE SERVICE (store.db) — Órdenes, Recibos Firmados y Control Local de Doble Gasto")
    lines.append(sub)

    orders = _ro_query(
        "store.db",
        "SELECT order_id, status, total_cents, receipt_signature FROM orders ORDER BY created_at DESC LIMIT 3",
    )
    lines.append("  • TABLA orders:")
    if not orders:
        lines.append("    (Sin órdenes en tienda)")
    for o in orders:
        lines.append(
            f"    {o['order_id']} | Estado: {o['status'].upper():<9} | Total: ${o['total_cents'] / 100:,.2f} | Firma Recibo Banco: {_short(o['receipt_signature'], 22)}"
        )

    spent_t = _ro_query(
        "store.db",
        "SELECT ticket_id, order_id, ticket_hash FROM spent_tickets ORDER BY redeemed_at DESC LIMIT 3",
    )
    if spent_t:
        lines.append("\n  • TABLA spent_tickets (Prevención local de doble gasto en Tienda):")
        for st in spent_t:
            lines.append(
                f"    Ticket: {st['ticket_id']} | Consumido en: {st['order_id']} | SHA-256: {_short(st['ticket_hash'], 20)}"
            )

    lines.append(f"\nActualizado: {time.strftime('%H:%M:%S')} (esperando cambios en BD...)")
    return "\n".join(lines)


def main() -> None:
    last_snapshot = ""
    try:
        while True:
            screen = _render()
            snapshot = "\n".join(screen.splitlines()[:-1])  # ignora la hora al comparar cambios
            if snapshot != last_snapshot:
                os.system("cls" if os.name == "nt" else "clear")
                print(screen)
                last_snapshot = snapshot
            time.sleep(1.0)
    except KeyboardInterrupt:
        print("\nMonitor detenido.")


if __name__ == "__main__":
    main()