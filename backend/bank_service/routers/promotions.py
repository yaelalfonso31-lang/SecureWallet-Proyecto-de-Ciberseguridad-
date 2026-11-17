from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from bank_service.database import get_db
from bank_service.deps import require_scope
from bank_service.models import Account, BankCustomer, Promotion, PromotionRedemption
from shared.timeutil import utcnow

router = APIRouter(tags=["promotions"])


class PromotionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str
    discount_percent: int


class PromotionDetailOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str
    discount_percent: int
    active: bool
    valid_until: datetime | None


class RedemptionOut(BaseModel):
    promotion_id: int
    account_id: int
    redeemed_at: datetime


@router.get("/promotions", response_model=list[PromotionOut])
def list_promotions(db: Session = Depends(get_db)):
    return list(db.scalars(select(Promotion).where(Promotion.active.is_(True))))


@router.get("/promotions/{promotion_id}", response_model=PromotionDetailOut)
def get_promotion(promotion_id: int, db: Session = Depends(get_db)):
    promo = db.get(Promotion, promotion_id)
    if promo is None:
        raise HTTPException(404, "Promoción no encontrada")
    return promo


@router.post("/promotions/{promotion_id}/redeem", response_model=RedemptionOut)
def redeem_promotion(
    promotion_id: int,
    customer: BankCustomer = Depends(require_scope("promotions:redeem")),
    db: Session = Depends(get_db),
):
    # 1. Buscar la cuenta del cliente
    account = db.scalar(select(Account).where(Account.customer_id == customer.id))
    if account is None:
        raise HTTPException(404, "El cliente no tiene cuenta")
    if account.status != "active":
        raise HTTPException(403, "La cuenta no está activa")

    # 2. Validar la promoción
    promo = db.get(Promotion, promotion_id)
    if promo is None or not promo.active:
        raise HTTPException(404, "Promoción no encontrada")
    if promo.valid_until is not None and promo.valid_until < utcnow():
        raise HTTPException(400, "Promoción vencida")

    # 3. Intentar insertar el canje — el UniqueConstraint(promotion_id, account_id)
    #    garantiza un solo canje por promoción por cuenta, sin race conditions.
    redemption = PromotionRedemption(
        promotion_id=promo.id,
        account_id=account.id,
    )
    db.add(redemption)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Ya canjeaste esta promoción")
    db.commit()
    db.refresh(redemption)

    return RedemptionOut(
        promotion_id=redemption.promotion_id,
        account_id=redemption.account_id,
        redeemed_at=redemption.redeemed_at,
    )
