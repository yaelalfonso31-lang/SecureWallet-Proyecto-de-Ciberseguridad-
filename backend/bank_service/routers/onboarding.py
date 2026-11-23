"""Apertura de cuenta del Banco simulado desde la app.

Antes solo se podía crear un cliente con `scripts/seed_bank.py`. Ahora el usuario de la
Wallet abre su cuenta desde la app: la Wallet certifica quién es (aserción firmada con
Ed25519) y el Banco crea el cliente y la cuenta. Después la app hace la vinculación normal
(`/oauth/authorize` + `/oauth/token`, con PKCE).
"""
import re
import secrets

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from bank_service.database import get_db
from bank_service.models import Account, BankCustomer, Movement
from bank_service.routers.oauth import WalletAssertion, _verify_assertion
from shared.config import settings
from shared.security.passwords import hash_password

router = APIRouter(prefix="/customers", tags=["onboarding"])

ACCOUNT_NUMBER_DIGITS = 16


def generate_account_number() -> str:
    """Número de cuenta aleatorio, nunca secuencial (no debe poder adivinarse)."""
    return "".join(str(secrets.randbelow(10)) for _ in range(ACCOUNT_NUMBER_DIGITS))


class OpenAccountIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)
    wallet_assertion: WalletAssertion

    @field_validator("password")
    @classmethod
    def password_strength(cls, value: str) -> str:
        if not re.search(r"[A-Za-z]", value) or not re.search(r"\d", value):
            raise ValueError("La contraseña debe incluir letras y números")
        return value


class OpenAccountOut(BaseModel):
    account_number_masked: str
    balance_cents: int
    currency: str = "MXN"


@router.post("/open-account", response_model=OpenAccountOut, status_code=201)
def open_account(body: OpenAccountIn, db: Session = Depends(get_db)):
    """Abre un cliente y una cuenta para el usuario de la Wallet que firma la aserción."""
    wallet_user_id = _verify_assertion(body.wallet_assertion)
    email = body.email.lower()

    # Un usuario de la Wallet solo puede tener una cuenta.
    if db.scalar(select(Account.id).where(Account.owner_ref == wallet_user_id)) is not None:
        raise HTTPException(409, "Ya tienes una cuenta bancaria")
    if db.scalar(select(BankCustomer.id).where(BankCustomer.email == email)) is not None:
        raise HTTPException(409, "No fue posible abrir la cuenta con ese correo")

    customer = BankCustomer(email=email, password_hash=hash_password(body.password), role="customer")
    db.add(customer)
    db.flush()

    opening_balance = settings.bank_open_account_balance_cents
    account = Account(
        owner_ref=wallet_user_id,
        customer_id=customer.id,
        account_number=generate_account_number(),
        balance_cents=opening_balance,
    )
    db.add(account)
    db.flush()
    db.add(
        Movement(
            account_id=account.id,
            kind="credit",
            amount_cents=opening_balance,
            balance_after_cents=opening_balance,
            concept="Depósito de apertura (simulación)",
            reference="opening",
        )
    )
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "No fue posible abrir la cuenta")

    return OpenAccountOut(
        account_number_masked=f"•••• {account.account_number[-4:]}",
        balance_cents=account.balance_cents,
    )
