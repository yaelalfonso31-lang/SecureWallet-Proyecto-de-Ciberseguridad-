import uuid


def ensure_bank_account(owner_ref, balance_cents=100_000_000, status="active"):
    """Crea (o actualiza) una cuenta del Banco con saldo, para las pruebas.

    Es idempotente: si la cuenta ya existe, solo resetea saldo y estado.
    Devuelve el id de la cuenta.
    """
    from sqlalchemy import select

    from bank_service.database import SessionLocal
    from bank_service.models import Account

    with SessionLocal() as db:
        account = db.scalar(select(Account).where(Account.owner_ref == owner_ref))
        if account is None:
            account = Account(owner_ref=owner_ref)
            db.add(account)
        account.balance_cents = balance_cents
        account.status = status
        db.commit()
        db.refresh(account)
        return account.id


def register_and_login(client, password="ClaveSegura123"):
    email = f"{uuid.uuid4().hex[:10]}@example.com"
    r = client.post("/auth/register", json={"email": email, "full_name": "Ana Prueba", "password": password})
    assert r.status_code == 201, r.text
    r = client.post("/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return email, {"Authorization": f"Bearer {r.json()['access_token']}"}
