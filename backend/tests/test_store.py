from shared.security.signing import verify
from tests.conftest import BANK_API_KEY, BANK_PUB, WALLET_PUB
from tests.helpers import register_and_login


def _bank_to_memory(monkeypatch, bank_client):
    """La Tienda 'habla' con el Banco de pruebas en memoria en lugar de la red."""
    monkeypatch.setattr(
        "store_service.routers.orders.process_payment",
        lambda payload: bank_client.post("/transactions/process", json=payload, headers={"X-API-Key": BANK_API_KEY}),
    )


def test_catalog_has_seed_products(store_client):
    r = store_client.get("/products")
    assert r.status_code == 200 and len(r.json()) >= 3


def test_full_purchase_flow_wallet_store_bank(wallet_client, store_client, bank_client, monkeypatch):
    _bank_to_memory(monkeypatch, bank_client)

    _, headers = register_and_login(wallet_client)
    product = store_client.get("/products").json()[0]

    # 1) La app crea la orden en la Tienda
    order = store_client.post(
        "/orders", json={"items": [{"product_id": product["id"], "quantity": 1}]}, headers=headers
    ).json()

    # 2) La Wallet firma la orden de pago
    signed = wallet_client.post(
        "/payments/authorize",
        json={"order_id": order["order_id"], "merchant": order["merchant"], "amount_cents": order["amount_cents"]},
        headers=headers,
    ).json()
    assert verify(WALLET_PUB, signed["order"], signed["signature"])

    # 3) La Tienda reenvía al Banco y verifica el recibo firmado
    r = store_client.post(f"/orders/{order['order_id']}/pay", json=signed, headers=headers)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["status"] == "paid"
    assert verify(BANK_PUB, data["receipt"], data["signature"])

    # 4) No se puede pagar dos veces la misma orden
    assert store_client.post(f"/orders/{order['order_id']}/pay", json=signed, headers=headers).status_code == 409


def test_pay_rejects_amount_mismatch(wallet_client, store_client):
    _, headers = register_and_login(wallet_client)
    product = store_client.get("/products").json()[0]
    order = store_client.post(
        "/orders", json={"items": [{"product_id": product["id"], "quantity": 1}]}, headers=headers
    ).json()
    signed = wallet_client.post(
        "/payments/authorize",
        json={"order_id": order["order_id"], "merchant": order["merchant"], "amount_cents": 100},
        headers=headers,
    ).json()
    assert store_client.post(f"/orders/{order['order_id']}/pay", json=signed, headers=headers).status_code == 400


def test_orders_require_authentication(store_client):
    product = store_client.get("/products").json()[0]
    body = {"items": [{"product_id": product["id"], "quantity": 1}]}
    assert store_client.post("/orders", json=body).status_code == 401
    assert store_client.get("/orders/ord_cualquiera").status_code == 401


def test_user_cannot_access_another_users_order(wallet_client, store_client):
    _, headers_a = register_and_login(wallet_client)
    _, headers_b = register_and_login(wallet_client)
    product = store_client.get("/products").json()[0]
    order = store_client.post(
        "/orders", json={"items": [{"product_id": product["id"], "quantity": 1}]}, headers=headers_a
    ).json()

    assert store_client.get(f"/orders/{order['order_id']}", headers=headers_a).status_code == 200
    assert store_client.get(f"/orders/{order['order_id']}", headers=headers_b).status_code == 404


def test_quote_requires_authentication(store_client):
    product = store_client.get("/products").json()[0]
    body = {"items": [{"product_id": product["id"], "quantity": 1}]}
    assert store_client.post("/cart/quote", json=body).status_code == 401


def test_quote_applies_percent_coupon(wallet_client, store_client):
    _, headers = register_and_login(wallet_client)
    product = store_client.get("/products").json()[0]
    body = {"items": [{"product_id": product["id"], "quantity": 2}], "coupon_code": "bienvenida10"}
    r = store_client.post("/cart/quote", json=body, headers=headers)
    assert r.status_code == 200, r.text
    q = r.json()
    subtotal = product["price_cents"] * 2
    assert q["subtotal_cents"] == subtotal
    assert q["discount_cents"] == subtotal * 10 // 100
    assert q["total_cents"] == subtotal - q["discount_cents"]
    assert q["coupon_code"] == "BIENVENIDA10"


def test_invalid_coupon_is_rejected_with_generic_message(wallet_client, store_client):
    _, headers = register_and_login(wallet_client)
    product = store_client.get("/products").json()[0]
    body = {"items": [{"product_id": product["id"], "quantity": 1}], "coupon_code": "NOEXISTE"}
    r = store_client.post("/cart/quote", json=body, headers=headers)
    assert r.status_code == 400 and r.json()["detail"] == "Cupón no válido"


def test_client_cannot_choose_the_total(wallet_client, store_client):
    _, headers = register_and_login(wallet_client)
    product = store_client.get("/products").json()[0]
    body = {"items": [{"product_id": product["id"], "quantity": 1}], "total_cents": 1, "discount_cents": 99999}
    order = store_client.post("/orders", json=body, headers=headers).json()
    assert order["amount_cents"] == product["price_cents"]


def test_duplicate_lines_are_merged_for_stock_check(wallet_client, store_client):
    _, headers = register_and_login(wallet_client)
    product = store_client.get("/products").json()[0]
    items = [{"product_id": product["id"], "quantity": 20}] * 2  # 40 en total: supera el máximo por producto
    r = store_client.post("/cart/quote", json={"items": items}, headers=headers)
    assert r.status_code == 400


def test_coupon_can_only_be_redeemed_once_per_user(wallet_client, store_client, bank_client, monkeypatch):
    _bank_to_memory(monkeypatch, bank_client)
    _, headers = register_and_login(wallet_client)
    product = store_client.get("/products").json()[0]
    body = {"items": [{"product_id": product["id"], "quantity": 1}], "coupon_code": "BIENVENIDA10"}

    def create():
        return store_client.post("/orders", json=body, headers=headers).json()

    def pay(order):
        signed = wallet_client.post(
            "/payments/authorize",
            json={"order_id": order["order_id"], "merchant": order["merchant"], "amount_cents": order["amount_cents"]},
            headers=headers,
        ).json()
        return store_client.post(f"/orders/{order['order_id']}/pay", json=signed, headers=headers)

    first, second = create(), create()  # las dos se crean antes de pagar cualquiera
    assert first["amount_cents"] < product["price_cents"]
    assert pay(first).status_code == 200
    assert pay(second).status_code == 409  # el cupón ya fue canjeado por este usuario
    # y ya no se puede cotizar con él
    assert store_client.post("/cart/quote", json=body, headers=headers).status_code == 400

class _FakeBankResponse:
    def __init__(self, status_code, body):
        self.status_code = status_code
        self._body = body

    def json(self):
        return self._body


def _create_and_sign(wallet_client, store_client, headers, product):
    order = store_client.post(
        "/orders", json={"items": [{"product_id": product["id"], "quantity": 1}]}, headers=headers
    ).json()
    signed = wallet_client.post(
        "/payments/authorize",
        json={"order_id": order["order_id"], "merchant": order["merchant"], "amount_cents": order["amount_cents"]},
        headers=headers,
    ).json()
    return order, signed


def _stock(store_client, product_id):
    return next(p["stock"] for p in store_client.get("/products").json() if p["id"] == product_id)


def test_rejected_payment_restores_stock_and_allows_retry(wallet_client, store_client, bank_client, monkeypatch):
    _, headers = register_and_login(wallet_client)
    product = store_client.get("/products").json()[0]
    order, signed = _create_and_sign(wallet_client, store_client, headers, product)
    pay_url = f"/orders/{order['order_id']}/pay"

    # El Banco rechaza el pago (por ejemplo, fondos insuficientes)
    monkeypatch.setattr(
        "store_service.routers.orders.process_payment",
        lambda payload: _FakeBankResponse(402, {"detail": "Fondos insuficientes"}),
    )
    assert store_client.post(pay_url, json=signed, headers=headers).status_code == 402
    assert store_client.get(f"/orders/{order['order_id']}", headers=headers).json()["status"] == "pending"
    assert _stock(store_client, product["id"]) == product["stock"]  # el stock se devolvió

    # La misma orden se puede volver a pagar
    _bank_to_memory(monkeypatch, bank_client)
    assert store_client.post(pay_url, json=signed, headers=headers).status_code == 200
    assert _stock(store_client, product["id"]) == product["stock"] - 1


def test_invalid_bank_receipt_marks_order_failed(wallet_client, store_client, bank_client, monkeypatch):
    _bank_to_memory(monkeypatch, bank_client)
    _, headers = register_and_login(wallet_client)
    product = store_client.get("/products").json()[0]
    order, signed = _create_and_sign(wallet_client, store_client, headers, product)

    monkeypatch.setattr("store_service.routers.orders.verify", lambda *args, **kwargs: False)
    pay_url = f"/orders/{order['order_id']}/pay"
    assert store_client.post(pay_url, json=signed, headers=headers).status_code == 502

    assert store_client.get(f"/orders/{order['order_id']}", headers=headers).json()["status"] == "failed"
    assert _stock(store_client, product["id"]) == product["stock"]
    # Una orden en failed no se reintenta sola
    assert store_client.post(pay_url, json=signed, headers=headers).status_code == 409