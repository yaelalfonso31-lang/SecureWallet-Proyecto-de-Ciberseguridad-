from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.orm import Session

from bank_service.database import get_db
from bank_service.deps import require_scope
from bank_service.models import Account, BankCustomer, Movement

router = APIRouter(tags=["accounts"])


class AccountOut(BaseModel):
    account_number_masked: str
    balance_cents: int
    currency: str
    status: str


class MovementOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    kind: str
    amount_cents: int
    balance_after_cents: int
    concept: str
    reference: str
    created_at: datetime


def _mask(account_number: str | None) -> str:
    """Nunca se devuelve el número de cuenta completo."""
    if not account_number:
        return "••••"
    return f"•••• {account_number[-4:]}"


def _get_own_account(db: Session, customer: BankCustomer) -> Account:
    """Cuenta del dueño del token. Anti-IDOR: jamás se usa un id que mande el cliente.

    Por eso no existen rutas `/accounts/{id}`.
    """
    account = db.scalar(select(Account).where(Account.customer_id == customer.id))
    if account is None:
        raise HTTPException(404, "Cuenta no encontrada")
    return account


@router.get("/accounts/me", response_model=AccountOut)
def get_my_account(
    db: Session = Depends(get_db),
    customer: BankCustomer = Depends(require_scope("accounts:read")),
):
    account = _get_own_account(db, customer)
    return AccountOut(
        account_number_masked=_mask(account.account_number),
        balance_cents=account.balance_cents,
        currency="MXN",
        status=account.status,
    )


@router.get("/accounts/me/movements", response_model=list[MovementOut])
def get_my_movements(
    limit: int = Query(20, ge=1, le=100),
    before: int | None = Query(default=None),
    db: Session = Depends(get_db),
    customer: BankCustomer = Depends(require_scope("accounts:read")),
):
    account = _get_own_account(db, customer)
    stmt = select(Movement).where(Movement.account_id == account.id)
    if before is not None:
        stmt = stmt.where(Movement.id < before)
    stmt = stmt.order_by(Movement.id.desc()).limit(limit)
    return list(db.scalars(stmt))
