"""B5 · Transferencias banco <-> wallet.

Usa el fixture `bank_customer` de B0 (token con scope transfers:write).
Los comprobantes de retiro se firman con WALLET_PRIV, simulando a la Wallet
(mientras Wallet no expone /wallet/withdraw).
"""
import secrets
import time
import uuid

from sqlalchemy import select

from bank_service.database import SessionLocal
from bank_service.models import Account, Movement, Transfer
from shared.config import settings
from shared.security.signing import sign, verify
from tests.conftest import BANK_PUB, WALLET_PRIV

INITIAL_BALANCE = 100_000  # saldo que crea el fixture bank_customer


def _balance(owner_ref):
    with SessionLocal() as db:
        return db.scalar(select(Account).where(Account.owner_ref == owner_ref)).balance_cents


def _movements(owner_ref):
    with SessionLocal() as db:
        account = db.scalar(select(Account).where(Account.owner_ref == owner_ref))
        return list(db.scalars(select(Movement).where(Movement.account_id == account.id)))


def _wallet_voucher(owner_ref, amount=500, direction="from_wallet"):
    """Comprobante de retiro firmado por la Wallet (simulado en las pruebas)."""
    voucher = {
        "transfer_id": uuid.uuid4().hex,
        "owner_ref": owner_ref,
        "amount_cents": amount,
        "nonce": secrets.token_hex(16),
        "timestamp": int(time.time()),
        "direction": direction,
    }
    return {"voucher": voucher, "signature": sign(WALLET_PRIV, voucher)}


def test_transfers_require_token(bank_client):
    r = bank_client.post("/transfers/to-wallet", json={"amount_cents": 1000, "idempotency_key": "k"})
    assert r.status_code == 401


def test_to_wallet_topup_ok(bank_client, bank_customer):
    r = bank_client.post(
        "/transfers/to-wallet",
        json={"amount_cents": 1000, "idempotency_key": "topup-1"},
        headers=bank_customer["auth_header"],
    )
    assert r.status_code == 200, r.text
    data = r.json()
    voucher = data["voucher"]
    assert voucher["amount_cents"] == 1000
    assert voucher["direction"] == "to_wallet"
    assert voucher["owner_ref"] == bank_customer["owner_ref"]
    # El comprobante lo firma el Banco: la Wallet lo puede verificar.
    assert verify(BANK_PUB, voucher, data["signature"])

    assert _balance(bank_customer["owner_ref"]) == INITIAL_BALANCE - 1000
    movements = _movements(bank_customer["owner_ref"])
    assert len(movements) == 1
    assert movements[0].kind == "debit" and movements[0].amount_cents == 1000
    assert movements[0].reference == voucher["transfer_id"]


def test_to_wallet_is_idempotent(bank_client, bank_customer):
    key = "misma-llave"
    body = {"amount_cents": 1000, "idempotency_key": key}
    headers = bank_customer["auth_header"]
    first = bank_client.post("/transfers/to-wallet", json=body, headers=headers).json()
    second = bank_client.post("/transfers/to-wallet", json=body, headers=headers).json()

    # Devuelve el MISMO comprobante y firma, y solo se cobró una vez.
    assert first == second
    assert _balance(bank_customer["owner_ref"]) == INITIAL_BALANCE - 1000
    assert len(_movements(bank_customer["owner_ref"])) == 1


def test_to_wallet_insufficient_funds(bank_client, bank_customer):
    # Mayor que el saldo (100_000) pero menor que el límite diario.
    r = bank_client.post(
        "/transfers/to-wallet",
        json={"amount_cents": 200_000, "idempotency_key": "grande"},
        headers=bank_customer["auth_header"],
    )
    assert r.status_code == 402


def test_to_wallet_daily_limit(bank_client, bank_customer, monkeypatch):
    monkeypatch.setattr(settings, "bank_transfer_daily_limit_cents", 1500)
    headers = bank_customer["auth_header"]
    ok = bank_client.post(
        "/transfers/to-wallet", json={"amount_cents": 1000, "idempotency_key": "a"}, headers=headers
    )
    assert ok.status_code == 200
    over = bank_client.post(
        "/transfers/to-wallet", json={"amount_cents": 1000, "idempotency_key": "b"}, headers=headers
    )
    assert over.status_code == 429  # 1000 + 1000 supera el límite de 1500


def test_from_wallet_ok(bank_client, bank_customer):
    payload = _wallet_voucher(bank_customer["owner_ref"], amount=500)
    r = bank_client.post("/transfers/from-wallet", json=payload, headers=bank_customer["auth_header"])
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "credited"

    assert _balance(bank_customer["owner_ref"]) == INITIAL_BALANCE + 500
    movements = _movements(bank_customer["owner_ref"])
    assert len(movements) == 1
    assert movements[0].kind == "credit" and movements[0].amount_cents == 500


def test_from_wallet_tampered_voucher_is_rejected(bank_client, bank_customer):
    payload = _wallet_voucher(bank_customer["owner_ref"], amount=500)
    payload["voucher"]["amount_cents"] = 1  # manipulado después de firmar
    r = bank_client.post("/transfers/from-wallet", json=payload, headers=bank_customer["auth_header"])
    assert r.status_code == 400


def test_from_wallet_replay_is_rejected(bank_client, bank_customer):
    payload = _wallet_voucher(bank_customer["owner_ref"], amount=500)
    headers = bank_customer["auth_header"]
    assert bank_client.post("/transfers/from-wallet", json=payload, headers=headers).status_code == 200
    # Reenvío del mismo comprobante: el nonce ya se usó.
    assert bank_client.post("/transfers/from-wallet", json=payload, headers=headers).status_code == 409


def test_from_wallet_other_owner_is_rejected(bank_client, bank_customer):
    # Comprobante válido y bien firmado, pero de OTRO usuario.
    payload = _wallet_voucher("otro-usuario", amount=500)
    r = bank_client.post("/transfers/from-wallet", json=payload, headers=bank_customer["auth_header"])
    assert r.status_code == 403
