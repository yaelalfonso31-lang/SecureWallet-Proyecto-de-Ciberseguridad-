import secrets
import time
import uuid
from datetime import timedelta

import pytest
from sqlalchemy import select

from bank_service.database import SessionLocal
from bank_service.models import Account, AuthorizationCode, BankCustomer
from bank_service.routers.oauth import pkce_s256
from shared.config import settings
from shared.schemas import PaymentOrder
from shared.security.hashing import sha256_hex
from shared.security.signing import generate_keypair, sign
from shared.security.tokens import create_access_token
from shared.timeutil import utcnow
from tests.conftest import BANK_API_KEY, WALLET_PRIV

PASSWORD = "ClaveSegura123"  # la del fixture bank_customer
CLIENT_ID = "securewallet-mobile"


def wallet_assertion(wallet_user_id=None, priv=WALLET_PRIV, audience="bank", timestamp=None):
    """Simula `POST /bank-link/assertion` de la Wallet (aún no existe)."""
    payload = {
        "wallet_user_id": wallet_user_id or f"wallet-{uuid.uuid4().hex}",
        "nonce": secrets.token_hex(16),
        "timestamp": timestamp or int(time.time()),
        "audience": audience,
    }
    return {"assertion": payload, "signature": sign(priv, payload)}


def new_verifier():
    return secrets.token_urlsafe(48)


def authorize_body(customer, verifier, assertion=None, **overrides):
    body = {
        "email": customer["email"],
        "password": PASSWORD,
        "code_challenge": pkce_s256(verifier),
        "code_challenge_method": "S256",
        "client_id": CLIENT_ID,
        "state": secrets.token_urlsafe(16),
        "wallet_assertion": assertion or wallet_assertion(),
    }
    body.update(overrides)
    return body


def get_code(bank_client, customer, verifier, **overrides):
    r = bank_client.post("/oauth/authorize", json=authorize_body(customer, verifier, **overrides))
    assert r.status_code == 200, r.text
    return r.json()["code"]


def exchange(bank_client, code, verifier):
    return bank_client.post(
        "/oauth/token", json={"code": code, "code_verifier": verifier, "client_id": CLIENT_ID}
    )


def test_pkce_s256_matches_rfc7636_vector():
    assert (
        pkce_s256("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    )


def test_full_flow_links_account_and_issues_bank_token(bank_client, bank_customer):
    verifier = new_verifier()
    wallet_user_id = f"wallet-{uuid.uuid4().hex}"
    body = authorize_body(bank_customer, verifier, assertion=wallet_assertion(wallet_user_id))

    r = bank_client.post("/oauth/authorize", json=body)
    assert r.status_code == 200, r.text
    assert r.json()["state"] == body["state"]

    r = exchange(bank_client, r.json()["code"], verifier)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["token_type"] == "bearer" and "accounts:read" in data["scope"].split()

    with SessionLocal() as db:
        account = db.get(Account, bank_customer["account_id"])
        assert account.owner_ref == wallet_user_id

    # El token emitido sirve para consultar la cuenta propia (B3).
    r = bank_client.get("/accounts/me", headers={"Authorization": f"Bearer {data['access_token']}"})
    assert r.status_code == 200
    assert r.json()["account_number_masked"].endswith(bank_customer["account_number"][-4:])


def test_linked_account_pays_orders_signed_for_that_wallet_user(bank_client, bank_customer):
    """Tras vincular, el `payer` que firma la Wallet se cobra de la cuenta ligada (B1)."""
    verifier = new_verifier()
    wallet_user_id = f"wallet-{uuid.uuid4().hex}"
    code = get_code(bank_client, bank_customer, verifier, assertion=wallet_assertion(wallet_user_id))
    assert exchange(bank_client, code, verifier).status_code == 200

    order = PaymentOrder(
        order_id="ord_" + secrets.token_hex(6),
        merchant="SecureStore",
        amount_cents=2_500,
        payer=wallet_user_id,
        nonce=secrets.token_hex(16),
        timestamp=int(time.time()),
    ).model_dump()
    r = bank_client.post(
        "/transactions/process",
        json={"order": order, "signature": sign(WALLET_PRIV, order)},
        headers={"X-API-Key": BANK_API_KEY},
    )
    assert r.status_code == 200, r.text
    with SessionLocal() as db:
        assert db.get(Account, bank_customer["account_id"]).balance_cents == 100_000 - 2_500


def test_code_is_stored_only_as_hash(bank_client, bank_customer):
    code = get_code(bank_client, bank_customer, new_verifier())
    with SessionLocal() as db:
        assert db.scalar(select(AuthorizationCode).where(AuthorizationCode.code_hash == code)) is None
        assert db.scalar(select(AuthorizationCode).where(AuthorizationCode.code_hash == sha256_hex(code)))


def test_wrong_verifier_is_rejected_and_burns_the_code(bank_client, bank_customer):
    verifier = new_verifier()
    code = get_code(bank_client, bank_customer, verifier)
    assert exchange(bank_client, code, new_verifier()).status_code == 400
    # El código ya se marcó como usado: ni con el verifier correcto se puede canjear.
    assert exchange(bank_client, code, verifier).status_code == 400


def test_reused_code_is_rejected(bank_client, bank_customer):
    verifier = new_verifier()
    code = get_code(bank_client, bank_customer, verifier)
    assert exchange(bank_client, code, verifier).status_code == 200
    assert exchange(bank_client, code, verifier).status_code == 400


def test_expired_code_is_rejected(bank_client, bank_customer):
    verifier = new_verifier()
    code = get_code(bank_client, bank_customer, verifier)
    with SessionLocal() as db:
        auth_code = db.scalar(select(AuthorizationCode).where(AuthorizationCode.code_hash == sha256_hex(code)))
        auth_code.expires_at = utcnow() - timedelta(seconds=1)
        db.commit()
    assert exchange(bank_client, code, verifier).status_code == 400


def test_unknown_code_is_rejected(bank_client):
    assert exchange(bank_client, secrets.token_urlsafe(32), new_verifier()).status_code == 400


def test_assertion_signed_by_other_key_is_rejected(bank_client, bank_customer):
    other_priv, _ = generate_keypair()
    body = authorize_body(bank_customer, new_verifier(), assertion=wallet_assertion(priv=other_priv))
    assert bank_client.post("/oauth/authorize", json=body).status_code == 400


def test_tampered_assertion_is_rejected(bank_client, bank_customer):
    assertion = wallet_assertion()
    assertion["assertion"]["wallet_user_id"] = "wallet-de-otra-persona"
    body = authorize_body(bank_customer, new_verifier(), assertion=assertion)
    assert bank_client.post("/oauth/authorize", json=body).status_code == 400


def test_assertion_for_other_audience_is_rejected(bank_client, bank_customer):
    body = authorize_body(bank_customer, new_verifier(), assertion=wallet_assertion(audience="store"))
    assert bank_client.post("/oauth/authorize", json=body).status_code == 400


def test_expired_assertion_is_rejected(bank_client, bank_customer):
    old = int(time.time()) - settings.order_max_age_seconds - 5
    body = authorize_body(bank_customer, new_verifier(), assertion=wallet_assertion(timestamp=old))
    assert bank_client.post("/oauth/authorize", json=body).status_code == 400


def test_plain_method_is_rejected(bank_client, bank_customer):
    verifier = new_verifier()
    body = authorize_body(bank_customer, verifier, code_challenge_method="plain")
    assert bank_client.post("/oauth/authorize", json=body).status_code == 400


def test_unknown_client_id_is_rejected(bank_client, bank_customer):
    body = authorize_body(bank_customer, new_verifier(), client_id="app-pirata")
    assert bank_client.post("/oauth/authorize", json=body).status_code == 400


def test_wrong_password_is_rejected(bank_client, bank_customer):
    body = authorize_body(bank_customer, new_verifier(), password="incorrecta")
    assert bank_client.post("/oauth/authorize", json=body).status_code == 400


def test_lockout_after_failed_attempts(bank_client, bank_customer):
    for _ in range(settings.max_failed_logins):
        body = authorize_body(bank_customer, new_verifier(), password="incorrecta")
        assert bank_client.post("/oauth/authorize", json=body).status_code == 400
    # Bloqueada: ni con la contraseña correcta.
    assert bank_client.post("/oauth/authorize", json=authorize_body(bank_customer, new_verifier())).status_code == 423


def test_wallet_user_cannot_be_linked_to_two_accounts(bank_client, bank_customer):
    # Otro cliente ya tiene ligado a este usuario de la Wallet.
    with SessionLocal() as db:
        other = BankCustomer(email=f"otro-{uuid.uuid4().hex}@example.com", password_hash="x")
        db.add(other)
        db.flush()
        taken_ref = f"wallet-{uuid.uuid4().hex}"
        db.add(Account(owner_ref=taken_ref, customer_id=other.id, account_number=str(uuid.uuid4().int)[:16]))
        db.commit()
    body = authorize_body(bank_customer, new_verifier(), assertion=wallet_assertion(taken_ref))
    assert bank_client.post("/oauth/authorize", json=body).status_code == 409


# --- El Banco no acepta tokens ajenos -------------------------------------------------

@pytest.mark.parametrize(
    "token_factory",
    [
        # JWT normal de la Wallet.
        lambda customer_id: create_access_token(customer_id),
        # Ni aunque diga aud="bank": está firmado con JWT_SECRET, no con BANK_JWT_SECRET.
        lambda customer_id: create_access_token(customer_id, {"aud": "bank"}),
    ],
)
def test_wallet_jwt_is_rejected_by_bank(bank_client, bank_customer, token_factory):
    token = token_factory(bank_customer["customer_id"])
    r = bank_client.get("/accounts/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 401
