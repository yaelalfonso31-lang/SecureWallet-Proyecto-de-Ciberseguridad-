"""Crea un administrador del Banco (si no existe) e imprime un token de 15 minutos.

Uso (desde la carpeta backend/):
    python scripts/bank_admin.py --email admin@banco.com

Sirve para probar `/admin/promotions` desde http://localhost:8002/docs (botón Authorize).
Es una herramienta de DESARROLLO: nunca la expongas ni guardes el token.
"""
import argparse
import getpass
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select  # noqa: E402

from bank_service.database import Base, SessionLocal, engine  # noqa: E402
from bank_service.deps import create_bank_token  # noqa: E402
from bank_service.models import BankCustomer  # noqa: E402
from shared.security.passwords import hash_password  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description="Crea un admin del Banco e imprime su token.")
    parser.add_argument("--email", required=True)
    args = parser.parse_args()

    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        admin = db.scalar(select(BankCustomer).where(BankCustomer.email == args.email.lower()))
        if admin is None:
            password = getpass.getpass("Contraseña del administrador (mínimo 10): ")
            if len(password) < 10:
                print("La contraseña debe tener al menos 10 caracteres.")
                sys.exit(1)
            admin = BankCustomer(email=args.email.lower(), password_hash=hash_password(password), role="admin")
            db.add(admin)
            db.commit()
            db.refresh(admin)
        elif admin.role != "admin":
            print("Ese correo ya existe y no es administrador.")
            sys.exit(1)
        customer_id = admin.id

    print("Token de administrador (15 min):")
    print(create_bank_token(customer_id, scopes=()))


if __name__ == "__main__":
    main()
