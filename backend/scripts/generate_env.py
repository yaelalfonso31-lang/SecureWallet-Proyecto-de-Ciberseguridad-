"""Genera un archivo .env con secretos aleatorios para desarrollo.

Uso (desde la carpeta backend/):
    python scripts/generate_env.py          # crea .env (no sobreescribe)
    python scripts/generate_env.py --force  # sobreescribe
"""
import base64
import os
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from shared.security.signing import generate_keypair  # noqa: E402

TARGET = Path(__file__).resolve().parents[1] / ".env"


def main() -> None:
    if TARGET.exists() and "--force" not in sys.argv:
        print(f"{TARGET} ya existe. Usa --force para sobreescribirlo.")
        return

    wallet_priv, wallet_pub = generate_keypair()
    bank_priv, bank_pub = generate_keypair()
    data_key = base64.urlsafe_b64encode(os.urandom(32)).decode()

    content = f"""ENVIRONMENT=dev

WALLET_DATABASE_URL=sqlite:///./wallet.db
BANK_DATABASE_URL=sqlite:///./bank.db
STORE_DATABASE_URL=sqlite:///./store.db

JWT_SECRET={secrets.token_urlsafe(48)}
ACCESS_TOKEN_MINUTES=15
BANK_JWT_SECRET={secrets.token_urlsafe(48)}

DATA_ENCRYPTION_KEY={data_key}

WALLET_SIGNING_PRIVATE_KEY={wallet_priv}
WALLET_SIGNING_PUBLIC_KEY={wallet_pub}
BANK_SIGNING_PRIVATE_KEY={bank_priv}
BANK_SIGNING_PUBLIC_KEY={bank_pub}

BANK_API_KEY={secrets.token_urlsafe(32)}
BANK_URL=http://localhost:8002
"""
    TARGET.write_text(content, encoding="utf-8")
    print(f"Listo: {TARGET} creado con secretos nuevos. No lo subas a GitHub.")


if __name__ == "__main__":
    main()
