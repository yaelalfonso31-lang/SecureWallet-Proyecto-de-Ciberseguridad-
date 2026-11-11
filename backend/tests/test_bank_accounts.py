"""B3 · Consulta de cuenta y movimientos (anti-IDOR).

Usa el fixture `bank_customer` de B0, sin necesitar el flujo OAuth de B2.
"""
from bank_service.database import SessionLocal
from bank_service.deps import ALL_SCOPES, create_bank_token
from bank_service.models import Account, BankCustomer, Movement
from shared.security.passwords import hash_password
from tests.test_bank import H, signed_order

INITIAL_BALANCE = 100_000  # saldo que crea el fixture bank_customer


def _make_customer(email, owner_ref, balance_cents, account_number):
    """Crea otro cliente con su cuenta y un token con todos los scopes."""
    with SessionLocal() as db:
        customer = BankCustomer(email=email, password_hash=hash_password("ClaveSegura123"), role="customer")
        db.add(customer)
        db.flush()
        account = Account(
            owner_ref=owner_ref,
            customer_id=customer.id,
            account_number=account_number,
            balance_cents=balance_cents,
        )
        db.add(account)
        db.commit()
        token = create_bank_token(customer.id, ALL_SCOPES)
        return {"auth_header": {"Authorization": f"Bearer {token}"}, "account_id": account.id}


def test_me_requires_token(bank_client):
    assert bank_client.get("/accounts/me").status_code == 401
    assert bank_client.get("/accounts/me/movements").status_code == 401


def test_me_returns_masked_account_and_balance(bank_client, bank_customer):
    r = bank_client.get("/accounts/me", headers=bank_customer["auth_header"])
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["balance_cents"] == INITIAL_BALANCE
    assert data["currency"] == "MXN"
    assert data["status"] == "active"
    # El número va enmascarado: nunca el completo, solo los últimos 4.
    assert data["account_number_masked"].startswith("•••• ")
    assert data["account_number_masked"].endswith(bank_customer["account_number"][-4:])
    assert bank_customer["account_number"] not in data["account_number_masked"]


def test_customer_cannot_see_other_customers_data(bank_client, bank_customer):
    other = _make_customer("otro@example.com", "wallet-otro", balance_cents=777_777, account_number="9999888877776666")
    # B tiene un movimiento que A no debe ver.
    with SessionLocal() as db:
        db.add(
            Movement(
                account_id=other["account_id"],
                kind="credit",
                amount_cents=1,
                balance_after_cents=777_778,
                concept="Movimiento de B",
                reference="ref-b",
            )
        )
        db.commit()

    me = bank_client.get("/accounts/me", headers=bank_customer["auth_header"]).json()
    assert me["balance_cents"] == INITIAL_BALANCE  # el saldo de A, no el 777_777 de B
    assert me["account_number_masked"].endswith(bank_customer["account_number"][-4:])

    movements = bank_client.get("/accounts/me/movements", headers=bank_customer["auth_header"]).json()
    assert all(m["reference"] != "ref-b" for m in movements)


def test_balance_matches_movements(bank_client, bank_customer):
    """El saldo de la cuenta coincide con los movimientos generados por los pagos."""
    owner_ref = bank_customer["owner_ref"]
    for amount in (1000, 500):
        r = bank_client.post("/transactions/process", json=signed_order(amount=amount, payer=owner_ref), headers=H)
        assert r.status_code == 200, r.text

    me = bank_client.get("/accounts/me", headers=bank_customer["auth_header"]).json()
    movements = bank_client.get("/accounts/me/movements", headers=bank_customer["auth_header"]).json()

    assert len(movements) == 2
    total_charged = sum(m["amount_cents"] for m in movements if m["kind"] == "debit")
    assert total_charged == 1500
    assert me["balance_cents"] == INITIAL_BALANCE - total_charged
    # El movimiento más reciente (primero en la lista) refleja el saldo actual.
    assert movements[0]["balance_after_cents"] == me["balance_cents"]


def test_movements_limit_is_validated(bank_client, bank_customer):
    headers = bank_customer["auth_header"]
    assert bank_client.get("/accounts/me/movements", params={"limit": 0}, headers=headers).status_code == 422
    assert bank_client.get("/accounts/me/movements", params={"limit": 101}, headers=headers).status_code == 422


def test_movements_pagination_with_before(bank_client, bank_customer):
    owner_ref = bank_customer["owner_ref"]
    for _ in range(3):
        bank_client.post("/transactions/process", json=signed_order(amount=100, payer=owner_ref), headers=H)

    headers = bank_customer["auth_header"]
    first_page = bank_client.get("/accounts/me/movements", params={"limit": 2}, headers=headers).json()
    assert len(first_page) == 2
    cursor = first_page[-1]["id"]
    second_page = bank_client.get(
        "/accounts/me/movements", params={"limit": 2, "before": cursor}, headers=headers
    ).json()
    assert len(second_page) == 1
    assert all(m["id"] < cursor for m in second_page)
