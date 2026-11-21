"""Pruebas de tickets electrónicos emitidos por el Banco y verificados por la Tienda."""
from sqlalchemy import select

from bank_service.database import SessionLocal
from bank_service.models import Account
from shared.security.signing import verify
from tests.conftest import BANK_API_KEY, BANK_PUB
from tests.helpers import register_and_login


def _link_customer_to_wallet_user(bank_customer, wallet_user_id: str):
    with SessionLocal() as db:
        acc = db.scalar(select(Account).where(Account.id == bank_customer["account_id"]))
        acc.owner_ref = wallet_user_id
        db.commit()


def _bank_redeem_to_memory(monkeypatch, bank_client):
    monkeypatch.setattr(
        "store_service.routers.orders.redeem_tickets",
        lambda payload: bank_client.post("/tickets/redeem", json=payload, headers={"X-API-Key": BANK_API_KEY}),
    )


def test_denominations_are_predefined(bank_client):
    r = bank_client.get("/tickets/denominations")
    assert r.status_code == 200
    assert r.json()["denominations_cents"] == [5000, 10000, 20000, 50000]


def test_purchase_tickets_validates_denomination_and_funds(bank_client, bank_customer):
    headers = bank_customer["auth_header"]
    # Denominación no permitida ($75)
    assert bank_client.post("/tickets/purchase", json={"denomination_cents": 7500}, headers=headers).status_code == 422
    # Compra válida de 2 tickets de $200
    r = bank_client.post("/tickets/purchase", json={"denomination_cents": 20000, "quantity": 2}, headers=headers)
    assert r.status_code == 201, r.text
    tickets = r.json()
    assert len(tickets) == 2
    assert all(verify(BANK_PUB, t["ticket"], t["signature"]) for t in tickets)
    # Saldo inicial era 100_000 -> quedan 60_000
    assert bank_client.get("/accounts/me", headers=headers).json()["balance_cents"] == 60_000


def test_full_purchase_with_tickets_refunds_change_and_blocks_double_spend(
    wallet_client, store_client, bank_client, bank_customer, monkeypatch
):
    _bank_redeem_to_memory(monkeypatch, bank_client)

    _, wallet_headers = register_and_login(wallet_client)
    user_id = wallet_client.get("/auth/me", headers=wallet_headers).json()["id"]
    _link_customer_to_wallet_user(bank_customer, user_id)
    bank_headers = bank_customer["auth_header"]

    # 1) Adquirir un ticket de $200 (20_000) para comprar el cable de $149 (14_900)
    cable = next(p for p in store_client.get("/products").json() if p["price_cents"] == 14900)
    purchased = bank_client.post(
        "/tickets/purchase", json={"denomination_cents": 20000, "quantity": 1}, headers=bank_headers
    ).json()
    signed_tickets = [{"ticket": t["ticket"], "signature": t["signature"]} for t in purchased]

    # 2) Crear orden en Tienda y pagar con el ticket
    order = store_client.post(
        "/orders", json={"items": [{"product_id": cable["id"], "quantity": 1}]}, headers=wallet_headers
    ).json()
    pay = store_client.post(
        f"/orders/{order['order_id']}/pay-with-tickets",
        json={"tickets": signed_tickets},
        headers=wallet_headers,
    )
    assert pay.status_code == 200, pay.text
    data = pay.json()
    assert data["status"] == "paid"
    assert data["receipt"]["payment_method"] == "tickets"
    assert data["receipt"]["change_cents"] == 5100  # 20_000 - 14_900
    assert verify(BANK_PUB, data["receipt"], data["signature"])

    # 3) El cambio ($51) volvió a la cuenta bancaria (100_000 - 20_000 + 5_100 = 85_100)
    assert bank_client.get("/accounts/me", headers=bank_headers).json()["balance_cents"] == 85_100

    # 4) El ticket ahora aparece como "spent"
    mine = bank_client.get("/tickets/me", headers=bank_headers).json()
    assert mine[0]["status"] == "spent" and mine[0]["spent_in_order_id"] == order["order_id"]

    # 5) Doble gasto rechazado (409) al intentar usar el mismo ticket en otra orden
    order2 = store_client.post(
        "/orders", json={"items": [{"product_id": cable["id"], "quantity": 1}]}, headers=wallet_headers
    ).json()
    replay = store_client.post(
        f"/orders/{order2['order_id']}/pay-with-tickets",
        json={"tickets": signed_tickets},
        headers=wallet_headers,
    )
    assert replay.status_code == 409


def test_store_rejects_tampered_ticket_before_contacting_bank(
    wallet_client, store_client, bank_client, bank_customer
):
    _, wallet_headers = register_and_login(wallet_client)
    user_id = wallet_client.get("/auth/me", headers=wallet_headers).json()["id"]
    _link_customer_to_wallet_user(bank_customer, user_id)

    purchased = bank_client.post(
        "/tickets/purchase", json={"denomination_cents": 5000, "quantity": 1}, headers=bank_customer["auth_header"]
    ).json()
    tampered = {"ticket": dict(purchased[0]["ticket"]), "signature": purchased[0]["signature"]}
    tampered["ticket"]["amount_cents"] = 50000  # altera $50 a $500

    product = store_client.get("/products").json()[0]
    order = store_client.post(
        "/orders", json={"items": [{"product_id": product["id"], "quantity": 1}]}, headers=wallet_headers
    ).json()
    r = store_client.post(
        f"/orders/{order['order_id']}/pay-with-tickets",
        json={"tickets": [tampered]},
        headers=wallet_headers,
    )
    assert r.status_code == 400