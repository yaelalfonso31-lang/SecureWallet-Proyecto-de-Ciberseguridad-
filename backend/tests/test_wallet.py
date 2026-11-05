import uuid

from tests.conftest import WALLET_PUB
from shared.security.signing import verify
from tests.helpers import register_and_login
from wallet_service.audit import verify_chain
from wallet_service.database import SessionLocal


def test_register_rejects_weak_password(wallet_client):
    r = wallet_client.post(
        "/auth/register",
        json={"email": f"{uuid.uuid4().hex[:8]}@example.com", "full_name": "Ana", "password": "corta1"},
    )
    assert r.status_code == 422


def test_login_and_me(wallet_client):
    email, headers = register_and_login(wallet_client)
    r = wallet_client.get("/auth/me", headers=headers)
    assert r.status_code == 200 and r.json()["email"] == email


def test_protected_route_requires_token(wallet_client):
    assert wallet_client.get("/cards").status_code == 401


def test_account_lockout_after_failed_attempts(wallet_client):
    email, _ = register_and_login(wallet_client)
    for _ in range(5):
        r = wallet_client.post("/auth/login", json={"email": email, "password": "incorrecta123"})
        assert r.status_code == 401
    r = wallet_client.post("/auth/login", json={"email": email, "password": "ClaveSegura123"})
    assert r.status_code == 423


def test_add_card_never_returns_full_number(wallet_client):
    _, headers = register_and_login(wallet_client)
    body = {"number": "4111 1111 1111 1111", "holder_name": "Ana Prueba", "exp_month": 12, "exp_year": 2030}
    r = wallet_client.post("/cards", json=body, headers=headers)
    assert r.status_code == 201
    data = r.json()
    assert data["last4"] == "1111" and data["brand"] == "visa" and data["token"].startswith("tok_")
    assert "4111111111111111" not in r.text
    assert len(wallet_client.get("/cards", headers=headers).json()) == 1


def test_add_card_rejects_invalid_luhn(wallet_client):
    _, headers = register_and_login(wallet_client)
    body = {"number": "4111111111111112", "holder_name": "Ana Prueba", "exp_month": 12, "exp_year": 2030}
    assert wallet_client.post("/cards", json=body, headers=headers).status_code == 422


def test_payment_authorization_is_signed(wallet_client):
    _, headers = register_and_login(wallet_client)
    r = wallet_client.post(
        "/payments/authorize",
        json={"order_id": "ord_demo", "merchant": "SecureStore", "amount_cents": 5000},
        headers=headers,
    )
    assert r.status_code == 200
    data = r.json()
    assert verify(WALLET_PUB, data["order"], data["signature"])


def test_audit_chain_is_valid_and_detects_tampering(wallet_client):
    register_and_login(wallet_client)
    from wallet_service.models import AuditLog

    with SessionLocal() as db:
        assert verify_chain(db)
        first = db.get(AuditLog, 1)
        first.detail = "manipulado"
        db.commit()
        assert not verify_chain(db)
        first.detail = ""
        db.commit()
        assert verify_chain(db)
