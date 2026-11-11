"""Crea un cliente del Banco con su cuenta y saldo, para la demo y las pruebas manuales.

Uso (desde la carpeta backend/):
    python scripts/seed_bank.py --email cliente@demo.com --owner-ref <wallet_user_id> --balance-cents 100000

No hay datos fijos: todo se pasa como argumentos y la contraseña se pide con
`getpass` (nunca fija ni por línea de comandos, para que no quede en el historial).
"""
import argparse
import getpass
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select  # noqa: E402

from bank_service.database import Base, SessionLocal, engine  # noqa: E402
from bank_service.models import Account, BankCustomer  # noqa: E402
from shared.security.passwords import hash_password  # noqa: E402

ACCOUNT_NUMBER_DIGITS = 16


def generate_account_number() -> str:
    """Número de cuenta aleatorio, nunca secuencial (no debe poder adivinarse)."""
    return "".join(str(secrets.randbelow(10)) for _ in range(ACCOUNT_NUMBER_DIGITS))


def main() -> None:
    parser = argparse.ArgumentParser(description="Crea un cliente del Banco con su cuenta y saldo.")
    parser.add_argument("--email", required=True, help="Email del cliente (único).")
    parser.add_argument("--owner-ref", required=True, help="id del usuario en la Wallet (el `payer` que firma).")
    parser.add_argument("--balance-cents", type=int, default=100_000, help="Saldo inicial en centavos (default 100000).")
    args = parser.parse_args()

    password = getpass.getpass("Contraseña del cliente: ")
    if len(password) < 10:
        print("La contraseña debe tener al menos 10 caracteres.")
        sys.exit(1)

    Base.metadata.create_all(engine)

    with SessionLocal() as db:
        if db.scalar(select(BankCustomer).where(BankCustomer.email == args.email.lower())):
            print(f"Ya existe un cliente con el email {args.email}.")
            sys.exit(1)
        if db.scalar(select(Account).where(Account.owner_ref == args.owner_ref)):
            print(f"Ya existe una cuenta para owner_ref {args.owner_ref}.")
            sys.exit(1)

        customer = BankCustomer(email=args.email.lower(), password_hash=hash_password(password), role="customer")
        db.add(customer)
        db.flush()
        account = Account(
            owner_ref=args.owner_ref,
            customer_id=customer.id,
            account_number=generate_account_number(),
            balance_cents=args.balance_cents,
        )
        db.add(account)
        db.commit()

        print("Cliente y cuenta creados:")
        print(f"  customer_id:   {customer.id}")
        print(f"  email:         {customer.email}")
        print(f"  owner_ref:     {account.owner_ref}")
        print(f"  account_number:{account.account_number}")
        print(f"  balance_cents: {account.balance_cents}")


if __name__ == "__main__":
    main()
