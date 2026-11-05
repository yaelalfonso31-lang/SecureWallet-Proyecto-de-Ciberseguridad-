import secrets
import time

from shared.schemas import PaymentOrder
from shared.security.signing import sign, verify
from tests.conftest import BANK_API_KEY, BANK_PUB, WALLET_PRIV

H = {"X-API-Key": BANK_API_KEY}


def signed_order(amount=1000, timestamp=None, priv=WALLET_PRIV, **overrides):
    order = PaymentOrder(
        order_id="ord_" + secrets.token_hex(6),
        merchant="SecureStore",
        amount_cents=amount,
        payer="user-test",
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
