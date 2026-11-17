"""Apertura de cuenta del Banco desde la app + canjes propios + administración de promociones."""
import secrets
import time
import uuid
from datetime import timedelta

from sqlalchemy import select

from bank_service.database import SessionLocal
from bank_service.deps import create_bank_token
from bank_service.models import Account, BankCustomer, Movement
from shared.config import settings
from shared.security.passwords import hash_password
from shared.security.signing import generate_keypair
from shared.timeutil import utcnow
from tests.test_bank_oauth import authorize_body, exchange, new_verifier, wallet_assertion


def _password():
    # Generada al correr la prueba: no hay credenciales escritas en el código.
    return "Aa1-" + secrets.token_urlsafe(12)


def _open_body(wallet_user_id=None, email=None, password=None, assertion=None):
    return {
        "email": email or f"nuevo-{uuid.uuid4().hex}@example.com",
        "password": password or _password(),
        "wallet_assertion": assertion or wallet_assertion(wallet_user_id),
    }


def test_open_account_creates_customer_account_and_opening_movement(bank_client):
    wallet_user_id = f"wallet-{uuid.uuid4().hex}"
    body = _open_body(wallet_user_id)
    r = bank_client.post("/customers/open-account", json=body)
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["balance_cents"] == settings.bank_open_account_balance_cents
    assert data["account_number_masked"].startswith("•••• ")
    with SessionLocal() as db:
        account = db.scalar(select(Account).where(Account.owner_ref == wallet_user_id))
        assert account is not None and account.status == "active"
        assert len(account.account_number) == 16
        assert db.scalar(select(Movement).where(Movement.account_id == account.id)).kind == "credit"
        customer = db.get(BankCustomer, account.customer_id)
        assert customer.role == "customer" and customer.password_hash != body["password"]


def test_open_account_then_link_with_oauth_pkce(bank_client):
    """Abrir la cuenta y vincularla con el flujo OAuth normal deja un token que sí funciona."""
    wallet_user_id = f"wallet-{uuid.uuid4().hex}"
    body = _open_body(wallet_user_id)
    assert bank_client.post("/customers/open-account", json=body).status_code == 201

    verifier = new_verifier()
    auth = bank_client.post(
        "/oauth/authorize",
        json=authorize_body(
            {"email": body["email"], "password": body["password"]},
            verifier,
            assertion=wallet_assertion(wallet_user_id),
        ),
    )
    assert auth.status_code == 200, auth.text
    token = exchange(bank_client, auth.json()["code"], verifier)
    assert token.status_code == 200, token.text
    headers = {"Authorization": f"Bearer {token.json()['access_token']}"}
    assert bank_client.get("/accounts/me", headers=headers).json()["balance_cents"] == settings.bank_open_account_balance_cents


def test_open_account_twice_for_same_wallet_user_is_rejected(bank_client):
    wallet_user_id = f"wallet-{uuid.uuid4().hex}"
    assert bank_client.post("/customers/open-account", json=_open_body(wallet_user_id)).status_code == 201
    r = bank_client.post("/customers/open-account", json=_open_body(wallet_user_id))
    assert r.status_code == 409


def test_open_account_with_existing_email_is_rejected(bank_client):
    email = f"dup-{uuid.uuid4().hex}@example.com"
    assert bank_client.post("/customers/open-account", json=_open_body(email=email)).status_code == 201
    assert bank_client.post("/customers/open-account", json=_open_body(email=email)).status_code == 409


def test_open_account_rejects_weak_password(bank_client):
    for weak in ("short1A", "soloLetrasLargas", "12345678901234"):
        r = bank_client.post("/customers/open-account", json=_open_body(password=weak))
        assert r.status_code == 422, weak


def test_open_account_rejects_forged_or_stale_assertion(bank_client):
    other_priv, _ = generate_keypair()
    forged = wallet_assertion(priv=other_priv)
    assert bank_client.post("/customers/open-account", json=_open_body(assertion=forged)).status_code == 400
    stale = wallet_assertion(timestamp=int(time.time()) - 3600)
    assert bank_client.post("/customers/open-account", json=_open_body(assertion=stale)).status_code == 400
    wrong_audience = wallet_assertion(audience="store")
    assert bank_client.post("/customers/open-account", json=_open_body(assertion=wrong_audience)).status_code == 400


def test_my_redemptions_requires_token(bank_client):
    assert bank_client.get("/promotions/me/redemptions").status_code == 401


def test_my_redemptions_lists_pending_canjes(bank_client, bank_customer):
    promo_id = bank_client.get("/promotions").json()[0]["id"]
    assert bank_client.get("/promotions/me/redemptions", headers=bank_customer["auth_header"]).json() == []

    r = bank_client.post(f"/promotions/{promo_id}/redeem", headers=bank_customer["auth_header"])
    assert r.status_code == 201, r.text

    rows = bank_client.get("/promotions/me/redemptions", headers=bank_customer["auth_header"]).json()
    assert len(rows) == 1
    assert rows[0]["promotion_id"] == promo_id and rows[0]["status"] == "pending"
    assert rows[0]["used_in_order_id"] is None and rows[0]["discount_percent"] > 0


def test_my_redemptions_never_shows_other_customers(bank_client, bank_customer):
    promo_id = bank_client.get("/promotions").json()[0]["id"]
    bank_client.post(f"/promotions/{promo_id}/redeem", headers=bank_customer["auth_header"])
    # Otro cliente con token propio no ve el canje ajeno.
    with SessionLocal() as db:
        other = BankCustomer(email=f"otro-{uuid.uuid4().hex}@example.com", password_hash=hash_password(_password()))
        db.add(other)
        db.flush()
        db.add(
            Account(
                owner_ref=f"wallet-{uuid.uuid4().hex}",
                customer_id=other.id,
                account_number=str(uuid.uuid4().int)[:16],
                balance_cents=0,
            )
        )
        db.commit()
        other_id = other.id
    headers = {"Authorization": f"Bearer {create_bank_token(other_id)}"}
    assert bank_client.get("/promotions/me/redemptions", headers=headers).json() == []


# ---------------- Administración de promociones (B6) ----------------


def _admin_headers():
    with SessionLocal() as db:
        admin = BankCustomer(
            email=f"admin-{uuid.uuid4().hex}@example.com", password_hash=hash_password(_password()), role="admin"
        )
        db.add(admin)
        db.commit()
        admin_id = admin.id
    return {"Authorization": f"Bearer {create_bank_token(admin_id, scopes=())}"}


def test_admin_endpoints_reject_non_admin(bank_client, bank_customer):
    assert bank_client.get("/admin/promotions").status_code == 401
    assert bank_client.get("/admin/promotions", headers=bank_customer["auth_header"]).status_code == 403
    r = bank_client.post(
        "/admin/promotions",
        json={"title": "x", "description": "y", "discount_percent": 5},
        headers=bank_customer["auth_header"],
    )
    assert r.status_code == 403


def test_admin_can_create_edit_and_deactivate_promotion(bank_client):
    headers = _admin_headers()
    created = bank_client.post(
        "/admin/promotions",
        json={"title": "Promo admin", "description": "Prueba", "discount_percent": 20},
        headers=headers,
    )
    assert created.status_code == 201, created.text
    promo_id = created.json()["id"]
    assert any(p["id"] == promo_id for p in bank_client.get("/promotions").json())

    patched = bank_client.patch(f"/admin/promotions/{promo_id}", json={"discount_percent": 25}, headers=headers)
    assert patched.status_code == 200 and patched.json()["discount_percent"] == 25

    off = bank_client.patch(f"/admin/promotions/{promo_id}", json={"active": False}, headers=headers)
    assert off.json()["active"] is False
    # Ya no aparece al público, pero el admin sí la ve.
    assert all(p["id"] != promo_id for p in bank_client.get("/promotions").json())
    assert any(p["id"] == promo_id for p in bank_client.get("/admin/promotions", headers=headers).json())


def test_admin_validation_and_not_found(bank_client):
    headers = _admin_headers()
    for bad in (0, 101, -5):
        r = bank_client.post(
            "/admin/promotions", json={"title": "x", "description": "y", "discount_percent": bad}, headers=headers
        )
        assert r.status_code == 422, bad
    assert bank_client.patch("/admin/promotions/999999", json={"active": False}, headers=headers).status_code == 404


def test_expired_promotion_is_hidden_from_public_list(bank_client):
    headers = _admin_headers()
    past = (utcnow() - timedelta(days=1)).isoformat()
    created = bank_client.post(
        "/admin/promotions",
        json={"title": "Vencida", "description": "Ya pasó", "discount_percent": 10, "valid_until": past},
        headers=headers,
    )
    assert created.status_code == 201
    assert all(p["id"] != created.json()["id"] for p in bank_client.get("/promotions").json())
