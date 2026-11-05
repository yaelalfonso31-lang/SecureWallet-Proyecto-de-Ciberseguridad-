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
