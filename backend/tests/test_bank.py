import secrets
import time

import pytest
from sqlalchemy import select

from bank_service.database import SessionLocal
from bank_service.models import Account, Movement
from shared.schemas import PaymentOrder
from shared.security.signing import sign, verify
from tests.conftest import BANK_API_KEY, BANK_PUB, WALLET_PRIV
from tests.helpers import ensure_bank_account

H = {"X-API-Key": BANK_API_KEY}
DEFAULT_PAYER = "user-test"
INITIAL_BALANCE = 10_000_000  # saldo de la cuenta de prueba (centavos)


@pytest.fixture(autouse=True)
def funded_account(bank_client):
    """Cada prueba parte de una cuenta dada de alta y con saldo conocido."""
    ensure_bank_account(DEFAULT_PAYER, balance_cents=INITIAL_BALANCE)


def signed_order(amount=1000, timestamp=None, priv=WALLET_PRIV, payer=DEFAULT_PAYER, **overrides):
    order = PaymentOrder(
        order_id="ord_" + secrets.token_hex(6),
        merchant="SecureStore",
        amount_cents=amount,
        payer=payer,
        nonce=secrets.token_hex(16),
        timestamp=timestamp or int(time.time()),
        **overrides,
    )
    return {"order": order.model_dump(), "signature": sign(priv, order.model_dump())}


def test_promotions_are_public(bank_client):
    r = bank_client.get("/promotions")
    assert r.status_code == 200 and len(r.json()) >= 1


def test_process_requires_api_key(bank_client):
    assert bank_client.post("/transactions/process", json=signed_order()).status_code == 401


def test_process_ok_returns_valid_signed_receipt(bank_client):
    r = bank_client.post("/transactions/process", json=signed_order(), headers=H)
    assert r.status_code == 200
    data = r.json()
    assert data["receipt"]["status"] == "approved"
    assert verify(BANK_PUB, data["receipt"], data["signature"])


def test_replay_is_rejected(bank_client):
    payload = signed_order()
    assert bank_client.post("/transactions/process", json=payload, headers=H).status_code == 200
    assert bank_client.post("/transactions/process", json=payload, headers=H).status_code == 409


def test_tampered_order_is_rejected(bank_client):
    payload = signed_order(amount=1000)
    payload["order"]["amount_cents"] = 1
    assert bank_client.post("/transactions/process", json=payload, headers=H).status_code == 400


def test_signature_from_other_key_is_rejected(bank_client):
    from shared.security.signing import generate_keypair

    other_priv, _ = generate_keypair()
    payload = signed_order(priv=other_priv)
    assert bank_client.post("/transactions/process", json=payload, headers=H).status_code == 400


def test_expired_order_is_rejected(bank_client):
    payload = signed_order(timestamp=int(time.time()) - 3600)
    assert bank_client.post("/transactions/process", json=payload, headers=H).status_code == 400


def test_insufficient_funds(bank_client):
    payload = signed_order(amount=99_999_999)
    assert bank_client.post("/transactions/process", json=payload, headers=H).status_code == 402


def test_payment_without_account_returns_404(bank_client):
    """Un payer sin cuenta dada de alta no puede pagar (antes se creaba sola con $1,000)."""
    payload = signed_order(payer="payer-sin-cuenta")
    assert bank_client.post("/transactions/process", json=payload, headers=H).status_code == 404


def test_frozen_account_returns_403(bank_client):
    ensure_bank_account("frozen-user", balance_cents=INITIAL_BALANCE, status="frozen")
    payload = signed_order(payer="frozen-user")
    assert bank_client.post("/transactions/process", json=payload, headers=H).status_code == 403


def test_payment_creates_movement_with_correct_balance(bank_client):
    """Cada cargo deja un movimiento inmutable con el saldo resultante correcto."""
    payload = signed_order(amount=1000)
    r = bank_client.post("/transactions/process", json=payload, headers=H)
    assert r.status_code == 200

    order_id = payload["order"]["order_id"]
    with SessionLocal() as db:
        account = db.scalar(select(Account).where(Account.owner_ref == DEFAULT_PAYER))
        assert account.balance_cents == INITIAL_BALANCE - 1000

        movements = db.scalars(select(Movement).where(Movement.reference == order_id)).all()
        assert len(movements) == 1
        movement = movements[0]
        assert movement.account_id == account.id
        assert movement.kind == "debit"
        assert movement.amount_cents == 1000
        assert movement.balance_after_cents == INITIAL_BALANCE - 1000
