"""Saldo de la Wallet: recarga desde el Banco, retiro hacia el Banco y el ciclo completo."""
import secrets
import time
import uuid

from sqlalchemy import select

from bank_service.database import SessionLocal
from bank_service.models import Account
from shared.security.signing import generate_keypair, sign, verify
from tests.conftest import BANK_PRIV, WALLET_PUB
from tests.helpers import register_and_login


def _user(wallet_client):
    _, headers = register_and_login(wallet_client)
    user_id = wallet_client.get("/auth/me", headers=headers).json()["id"]
    return user_id, headers


def _bank_voucher(owner_ref, amount=5000, direction="to_wallet", priv=BANK_PRIV, timestamp=None, transfer_id=None):
    """Comprobante de recarga firmado por el Banco (simulado)."""
    voucher = {
        "transfer_id": transfer_id or uuid.uuid4().hex,
        "owner_ref": owner_ref,
        "amount_cents": amount,
        "nonce": secrets.token_hex(16),
        "timestamp": timestamp or int(time.time()),
        "direction": direction,
    }
    return {"voucher": voucher, "signature": sign(priv, voucher)}


def _balance(wallet_client, headers):
    return wallet_client.get("/wallet/balance", headers=headers).json()["balance_cents"]


def test_wallet_endpoints_require_token(wallet_client):
    assert wallet_client.get("/wallet/balance").status_code == 401
    assert wallet_client.get("/wallet/movements").status_code == 401
    assert wallet_client.post("/wallet/withdraw", json={"amount_cents": 100}).status_code == 401


def test_new_wallet_starts_at_zero(wallet_client):
    _, headers = _user(wallet_client)
    assert _balance(wallet_client, headers) == 0
    assert wallet_client.get("/wallet/movements", headers=headers).json() == []


def test_topup_credits_balance_and_records_movement(wallet_client):
    user_id, headers = _user(wallet_client)
    r = wallet_client.post("/wallet/topup", json=_bank_voucher(user_id, 7500), headers=headers)
    assert r.status_code == 200, r.text
    assert r.json() == {"status": "credited", "balance_cents": 7500}
    assert _balance(wallet_client, headers) == 7500
    movements = wallet_client.get("/wallet/movements", headers=headers).json()
    assert len(movements) == 1
    assert movements[0]["kind"] == "credit" and movements[0]["balance_after_cents"] == 7500


def test_topup_is_idempotent_same_voucher_credits_only_once(wallet_client):
    user_id, headers = _user(wallet_client)
    body = _bank_voucher(user_id, 3000)
    assert wallet_client.post("/wallet/topup", json=body, headers=headers).json()["status"] == "credited"
    again = wallet_client.post("/wallet/topup", json=body, headers=headers)
    assert again.status_code == 200 and again.json() == {"status": "already_credited", "balance_cents": 3000}
    assert _balance(wallet_client, headers) == 3000


def test_topup_rejects_forged_signature_wrong_owner_direction_and_expired(wallet_client):
    user_id, headers = _user(wallet_client)
    other_priv, _ = generate_keypair()
    assert wallet_client.post("/wallet/topup", json=_bank_voucher(user_id, priv=other_priv), headers=headers).status_code == 400

    tampered = _bank_voucher(user_id, 1000)
    tampered["voucher"]["amount_cents"] = 99999
    assert wallet_client.post("/wallet/topup", json=tampered, headers=headers).status_code == 400

    # Comprobante de otro usuario (anti-IDOR).
    assert wallet_client.post("/wallet/topup", json=_bank_voucher("otro-usuario"), headers=headers).status_code == 403
    # Un comprobante de retiro no sirve como recarga.
    assert wallet_client.post("/wallet/topup", json=_bank_voucher(user_id, direction="from_wallet"), headers=headers).status_code == 400
    # Vencido.
    old = _bank_voucher(user_id, timestamp=int(time.time()) - 86_400)
    assert wallet_client.post("/wallet/topup", json=old, headers=headers).status_code == 400
    assert _balance(wallet_client, headers) == 0


def test_withdraw_requires_funds_and_signs_voucher(wallet_client):
    user_id, headers = _user(wallet_client)
    assert wallet_client.post("/wallet/withdraw", json={"amount_cents": 100}, headers=headers).status_code == 402

    wallet_client.post("/wallet/topup", json=_bank_voucher(user_id, 10_000), headers=headers)
    r = wallet_client.post("/wallet/withdraw", json={"amount_cents": 4000}, headers=headers)
    assert r.status_code == 200, r.text
    data = r.json()
    assert verify(WALLET_PUB, data["voucher"], data["signature"])
    assert data["voucher"]["direction"] == "from_wallet" and data["voucher"]["owner_ref"] == user_id
    assert _balance(wallet_client, headers) == 6000
    assert wallet_client.post("/wallet/withdraw", json={"amount_cents": 6001}, headers=headers).status_code == 402
    assert wallet_client.post("/wallet/withdraw", json={"amount_cents": 0}, headers=headers).status_code == 422


def test_balances_are_isolated_between_users(wallet_client):
    user_a, headers_a = _user(wallet_client)
    _, headers_b = _user(wallet_client)
    wallet_client.post("/wallet/topup", json=_bank_voucher(user_a, 2000), headers=headers_a)
    assert _balance(wallet_client, headers_a) == 2000
    assert _balance(wallet_client, headers_b) == 0


def test_full_cycle_bank_to_wallet_and_back(wallet_client, bank_client, bank_customer):
    """Banco -> Wallet (recarga) y Wallet -> Banco (retiro), con comprobantes firmados reales."""
    user_id, wallet_headers = _user(wallet_client)
    # La cuenta del cliente del Banco queda ligada a este usuario de la Wallet.
    with SessionLocal() as db:
        account = db.scalar(select(Account).where(Account.id == bank_customer["account_id"]))
        account.owner_ref = user_id
        db.commit()
    bank_headers = bank_customer["auth_header"]

    def bank_balance():
        return bank_client.get("/accounts/me", headers=bank_headers).json()["balance_cents"]

    start = bank_balance()  # 100_000

    # 1) Recarga: el Banco descuenta y firma; la Wallet verifica y abona.
    topup = bank_client.post(
        "/transfers/to-wallet", json={"amount_cents": 20_000, "idempotency_key": uuid.uuid4().hex}, headers=bank_headers
    )
    assert topup.status_code == 200, topup.text
    credited = wallet_client.post("/wallet/topup", json=topup.json(), headers=wallet_headers)
    assert credited.status_code == 200 and credited.json()["balance_cents"] == 20_000
    assert bank_balance() == start - 20_000

    # 2) Retiro: la Wallet descuenta y firma; el Banco verifica y abona.
    voucher = wallet_client.post("/wallet/withdraw", json={"amount_cents": 5_000}, headers=wallet_headers)
    assert voucher.status_code == 200, voucher.text
    back = bank_client.post("/transfers/from-wallet", json=voucher.json(), headers=bank_headers)
    assert back.status_code == 200, back.text
    assert _balance(wallet_client, wallet_headers) == 15_000
    assert bank_balance() == start - 20_000 + 5_000

    # El mismo comprobante de retiro no se puede cobrar dos veces en el Banco.
    assert bank_client.post("/transfers/from-wallet", json=voucher.json(), headers=bank_headers).status_code == 409


def test_p2p_transfer_moves_real_balance_and_records_movements(wallet_client):
    user_a, headers_a = _user(wallet_client)
    email_b, headers_b = register_and_login(wallet_client)

    wallet_client.post("/wallet/topup", json=_bank_voucher(user_a, 10_000), headers=headers_a)

    # No permite enviarse a sí mismo
    email_a = wallet_client.get("/auth/me", headers=headers_a).json()["email"]
    assert wallet_client.post(
        "/wallet/transfer", json={"recipient_email": email_a, "amount_cents": 1000}, headers=headers_a
    ).status_code == 400

    # Transferencia válida hacia B
    r = wallet_client.post(
        "/wallet/transfer",
        json={"recipient_email": email_b, "amount_cents": 3500, "note": "Cena"},
        headers=headers_a,
    )
    assert r.status_code == 200, r.text
    assert _balance(wallet_client, headers_a) == 6500
    assert _balance(wallet_client, headers_b) == 3500

    mov_a = wallet_client.get("/wallet/movements", headers=headers_a).json()
    mov_b = wallet_client.get("/wallet/movements", headers=headers_b).json()
    assert mov_a[0]["kind"] == "debit" and mov_a[0]["amount_cents"] == 3500
    assert mov_b[0]["kind"] == "credit" and mov_b[0]["amount_cents"] == 3500