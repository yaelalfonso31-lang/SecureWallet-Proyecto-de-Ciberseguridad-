"""B4-a · Canje de promociones (Persona 2).

Usa el fixture `bank_customer` de B0, sin necesitar el flujo OAuth de B2.
"""
from datetime import timedelta

from bank_service.database import SessionLocal
from bank_service.deps import create_bank_token
from bank_service.models import Promotion
from shared.timeutil import utcnow


def _seed_promotion(*, active=True, valid_until=None):
    """Crea una promoción directamente en la BD y devuelve su id."""
    with SessionLocal() as db:
        promo = Promotion(
            title="Promo de prueba",
            description="Descripción de prueba",
            discount_percent=20,
            active=active,
            valid_until=valid_until,
        )
        db.add(promo)
        db.commit()
        return promo.id


# ───────────────────── GET /promotions/{id} ─────────────────────


def test_promotion_detail_returns_fields(bank_client):
    promo_id = _seed_promotion()
    r = bank_client.get(f"/promotions/{promo_id}")
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["id"] == promo_id
    assert data["title"] == "Promo de prueba"
    assert data["description"] == "Descripción de prueba"
    assert data["discount_percent"] == 20
    assert data["active"] is True


def test_promotion_detail_not_found(bank_client):
    r = bank_client.get("/promotions/999999")
    assert r.status_code == 404


# ───────────────────── POST /promotions/{id}/redeem ─────────────────────


def test_redeem_success(bank_client, bank_customer):
    promo_id = _seed_promotion()
    r = bank_client.post(
        f"/promotions/{promo_id}/redeem",
        headers=bank_customer["auth_header"],
    )
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["promotion_id"] == promo_id
    assert data["account_id"] == bank_customer["account_id"]
    assert "redeemed_at" in data


def test_redeem_duplicate_returns_409(bank_client, bank_customer):
    promo_id = _seed_promotion()
    r1 = bank_client.post(
        f"/promotions/{promo_id}/redeem",
        headers=bank_customer["auth_header"],
    )
    assert r1.status_code == 201

    r2 = bank_client.post(
        f"/promotions/{promo_id}/redeem",
        headers=bank_customer["auth_header"],
    )
    assert r2.status_code == 409


def test_redeem_expired_returns_400(bank_client, bank_customer):
    promo_id = _seed_promotion(valid_until=utcnow() - timedelta(days=1))
    r = bank_client.post(
        f"/promotions/{promo_id}/redeem",
        headers=bank_customer["auth_header"],
    )
    assert r.status_code == 400


def test_redeem_without_token_returns_401(bank_client):
    promo_id = _seed_promotion()
    r = bank_client.post(f"/promotions/{promo_id}/redeem")
    assert r.status_code == 401


def test_redeem_without_scope_returns_403(bank_client, bank_customer):
    # Token sin el scope promotions:redeem
    token = create_bank_token(bank_customer["customer_id"], scopes=("accounts:read",))
    r = bank_client.post(
        f"/promotions/{_seed_promotion()}/redeem",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 403


def test_redeem_inactive_promotion_returns_404(bank_client, bank_customer):
    promo_id = _seed_promotion(active=False)
    r = bank_client.post(
        f"/promotions/{promo_id}/redeem",
        headers=bank_customer["auth_header"],
    )
    assert r.status_code == 404
