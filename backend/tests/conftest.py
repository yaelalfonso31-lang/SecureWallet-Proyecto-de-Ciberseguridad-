"""Configuración de pruebas: claves y bases de datos temporales, nunca las reales."""
import base64
import os
import tempfile

from shared.security.signing import generate_keypair

_tmp = tempfile.mkdtemp()
WALLET_PRIV, WALLET_PUB = generate_keypair()
BANK_PRIV, BANK_PUB = generate_keypair()
BANK_API_KEY = "test-bank-api-key"

os.environ.update(
    {
        "WALLET_DATABASE_URL": f"sqlite:///{_tmp}/wallet.db",
        "BANK_DATABASE_URL": f"sqlite:///{_tmp}/bank.db",
        "STORE_DATABASE_URL": f"sqlite:///{_tmp}/store.db",
        "JWT_SECRET": "t" * 48,
        "BANK_JWT_SECRET": "b" * 48,
        "DATA_ENCRYPTION_KEY": base64.urlsafe_b64encode(os.urandom(32)).decode(),
        "WALLET_SIGNING_PRIVATE_KEY": WALLET_PRIV,
        "WALLET_SIGNING_PUBLIC_KEY": WALLET_PUB,
        "BANK_SIGNING_PRIVATE_KEY": BANK_PRIV,
        "BANK_SIGNING_PUBLIC_KEY": BANK_PUB,
        "BANK_API_KEY": BANK_API_KEY,
    }
)

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from bank_service.main import app as bank_app  # noqa: E402
from store_service.main import app as store_app  # noqa: E402
from wallet_service.main import app as wallet_app  # noqa: E402


@pytest.fixture(scope="session")
def wallet_client():
    with TestClient(wallet_app) as client:
        yield client


@pytest.fixture(scope="session")
def bank_client():
    with TestClient(bank_app) as client:
        yield client


@pytest.fixture(scope="session")
def store_client():
    with TestClient(store_app) as client:
        yield client


@pytest.fixture()
def bank_customer(bank_client):
    """Cliente del Banco con su cuenta y saldo, y un token con TODOS los scopes.

    Permite que la Persona 1 pruebe cuentas, movimientos y transferencias sin
    necesitar el flujo OAuth de B2. Depende de `bank_client` para que las tablas
    ya existan (se crean en el lifespan de la app).
    """
    import uuid

    from bank_service.database import SessionLocal
    from bank_service.deps import ALL_SCOPES, create_bank_token
    from bank_service.models import Account, BankCustomer
    from shared.security.passwords import hash_password

    unique = uuid.uuid4().hex
    email = f"customer-{unique}@example.com"
    owner_ref = f"wallet-{unique}"
    account_number = str(uuid.uuid4().int)[:16]

    with SessionLocal() as db:
        customer = BankCustomer(email=email, password_hash=hash_password("ClaveSegura123"), role="customer")
        db.add(customer)
        db.flush()
        account = Account(
            owner_ref=owner_ref,
            customer_id=customer.id,
            account_number=account_number,
            balance_cents=100_000,
        )
        db.add(account)
        db.commit()
        customer_id = customer.id
        account_id = account.id

    token = create_bank_token(customer_id, ALL_SCOPES)
    return {
        "customer_id": customer_id,
        "email": email,
        "account_id": account_id,
        "account_number": account_number,
        "owner_ref": owner_ref,
        "token": token,
        "auth_header": {"Authorization": f"Bearer {token}"},
    }
