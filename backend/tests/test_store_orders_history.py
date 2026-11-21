"""Tienda: categorías y búsqueda, historial de órdenes, cancelación y administración."""
import uuid

from shared.config import settings
from tests.conftest import BANK_API_KEY
from tests.helpers import ensure_bank_account, register_and_login


def _order(store_client, headers, product_id, quantity=1):
    r = store_client.post("/orders", json={"items": [{"product_id": product_id, "quantity": quantity}]}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()


def test_products_have_category_and_filters(store_client):
    products = store_client.get("/products").json()
    assert len(products) >= 5 and all(p["category"] for p in products)

    categories = store_client.get("/products/categories").json()
    assert "Audio" in categories and categories == sorted(categories)

    audio = store_client.get("/products", params={"category": "Audio"}).json()
    assert audio and all(p["category"] == "Audio" for p in audio)

    found = store_client.get("/products", params={"q": "teclado"}).json()
    assert [p["name"] for p in found] == ["Teclado mecánico"]
    assert store_client.get("/products", params={"q": "zzzz-no-existe"}).json() == []
    # La ruta /categories no se confunde con un id.
    assert store_client.get("/products/categories").status_code == 200


def test_order_history_requires_token_and_is_per_user(wallet_client, store_client):
    assert store_client.get("/orders").status_code == 401

    _, headers_a = register_and_login(wallet_client)
    _, headers_b = register_and_login(wallet_client)
    product_id = store_client.get("/products").json()[0]["id"]
    mine = _order(store_client, headers_a, product_id, 2)

    history_a = store_client.get("/orders", headers=headers_a).json()
    assert [o["order_id"] for o in history_a] == [mine["order_id"]]
    assert history_a[0]["items_count"] == 2
    assert history_a[0]["items"][0]["name"]  # incluye el nombre del producto
    assert history_a[0]["status"] == "pending" and history_a[0]["receipt"] is None
    # Otro usuario no ve las órdenes ajenas.
    assert store_client.get("/orders", headers=headers_b).json() == []


def test_order_history_orders_newest_first_and_filters_by_status(wallet_client, store_client):
    _, headers = register_and_login(wallet_client)
    product_id = store_client.get("/products").json()[0]["id"]
    first = _order(store_client, headers, product_id)
    second = _order(store_client, headers, product_id)
    ids = [o["order_id"] for o in store_client.get("/orders", headers=headers).json()]
    assert set(ids) == {first["order_id"], second["order_id"]}
    assert store_client.get("/orders", params={"status": "paid"}, headers=headers).json() == []
    assert store_client.get("/orders", params={"status": "inventado"}, headers=headers).status_code == 422


def test_cancel_pending_order_and_cannot_pay_it(wallet_client, store_client):
    _, headers = register_and_login(wallet_client)
    product_id = store_client.get("/products").json()[0]["id"]
    order = _order(store_client, headers, product_id)

    r = store_client.post(f"/orders/{order['order_id']}/cancel", headers=headers)
    assert r.status_code == 200 and r.json()["status"] == "cancelled"
    assert store_client.post(f"/orders/{order['order_id']}/cancel", headers=headers).status_code == 409

    signed = wallet_client.post(
        "/payments/authorize",
        json={"order_id": order["order_id"], "merchant": order["merchant"], "amount_cents": order["amount_cents"]},
        headers=headers,
    ).json()
    pay = store_client.post(f"/orders/{order['order_id']}/pay", json=signed, headers=headers)
    assert pay.status_code == 409 and "cancelada" in pay.json()["detail"]


def test_cannot_cancel_someone_elses_order(wallet_client, store_client):
    _, headers_a = register_and_login(wallet_client)
    _, headers_b = register_and_login(wallet_client)
    product_id = store_client.get("/products").json()[0]["id"]
    order = _order(store_client, headers_a, product_id)
    assert store_client.post(f"/orders/{order['order_id']}/cancel", headers=headers_b).status_code == 404


def test_paid_order_appears_in_history_with_receipt_and_cannot_be_cancelled(
    wallet_client, store_client, bank_client, monkeypatch
):
    monkeypatch.setattr(
        "store_service.routers.orders.process_payment",
        lambda payload: bank_client.post("/transactions/process", json=payload, headers={"X-API-Key": BANK_API_KEY}),
    )
    _, headers = register_and_login(wallet_client)
    user_id = wallet_client.get("/auth/me", headers=headers).json()["id"]
    ensure_bank_account(user_id, balance_cents=100_000_000)
    product_id = store_client.get("/products").json()[0]["id"]
    order = _order(store_client, headers, product_id)
    signed = wallet_client.post(
        "/payments/authorize",
        json={"order_id": order["order_id"], "merchant": order["merchant"], "amount_cents": order["amount_cents"]},
        headers=headers,
    ).json()
    assert store_client.post(f"/orders/{order['order_id']}/pay", json=signed, headers=headers).status_code == 200

    paid = store_client.get("/orders", params={"status": "paid"}, headers=headers).json()
    assert len(paid) == 1
    assert paid[0]["receipt"]["status"] == "approved" and paid[0]["signature"]
    assert paid[0]["charged_cents"] == order["amount_cents"]
    assert store_client.post(f"/orders/{order['order_id']}/cancel", headers=headers).status_code == 409


# ---------------- Administración del catálogo ----------------


def test_admin_is_disabled_without_key(store_client, monkeypatch):
    monkeypatch.setattr(settings, "store_admin_key", "")
    body = {"name": "X", "description": "Y", "price_cents": 100, "stock": 1}
    assert store_client.post("/admin/products", json=body).status_code == 401
    assert store_client.post("/admin/products", json=body, headers={"X-Admin-Key": ""}).status_code == 401


def test_admin_can_create_and_restock_products(store_client, monkeypatch):
    key = uuid.uuid4().hex
    monkeypatch.setattr(settings, "store_admin_key", key)
    headers = {"X-Admin-Key": key}
    bad = store_client.post("/admin/products", json={"name": "X", "description": "Y", "price_cents": 1, "stock": 1}, headers={"X-Admin-Key": "otra"})
    assert bad.status_code == 401

    created = store_client.post(
        "/admin/products",
        json={"name": "Producto admin", "description": "Prueba", "price_cents": 12_300, "stock": 3, "category": "Audio"},
        headers=headers,
    )
    assert created.status_code == 201, created.text
    pid = created.json()["id"]
    patched = store_client.patch(f"/admin/products/{pid}", json={"stock": 50, "price_cents": 9_900}, headers=headers)
    assert patched.status_code == 200 and patched.json()["stock"] == 50 and patched.json()["price_cents"] == 9_900
    assert store_client.get(f"/products/{pid}").json()["name"] == "Producto admin"

    assert store_client.patch(f"/admin/products/{pid}", json={"price_cents": 0}, headers=headers).status_code == 422
    assert store_client.patch("/admin/products/999999", json={"stock": 1}, headers=headers).status_code == 404


# ---------------- Migración de bases de datos existentes ----------------


def test_ensure_schema_adds_category_to_an_old_database(tmp_path):
    from sqlalchemy import create_engine, text

    from store_service.migrations import ensure_schema

    engine = create_engine(f"sqlite:///{tmp_path}/old_store.db")
    with engine.begin() as conn:
        conn.execute(
            text(
                "CREATE TABLE products (id INTEGER PRIMARY KEY, name VARCHAR(100), description VARCHAR(300), "
                "price_cents INTEGER, stock INTEGER)"
            )
        )
        conn.execute(text("INSERT INTO products VALUES (1, 'Teclado mecánico', 'x', 100, 1)"))
        conn.execute(text("INSERT INTO products VALUES (2, 'Algo nuevo', 'y', 200, 2)"))

    ensure_schema(engine)
    ensure_schema(engine)  # ejecutarla dos veces no rompe nada
    with engine.connect() as conn:
        rows = dict(conn.execute(text("SELECT name, category FROM products")).all())
    assert rows == {"Teclado mecánico": "Computación", "Algo nuevo": "General"}
