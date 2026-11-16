from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict
from sqlalchemy import or_, select
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
    valid_until: datetime | None = None


class RedemptionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    promotion_id: int
    account_id: int
    redeemed_at: datetime
    used_in_order_id: str | None = None


@router.get("/promotions", response_model=list[PromotionOut])
def list_promotions(db: Session = Depends(get_db)):
    now = utcnow()
    stmt = select(Promotion).where(
        Promotion.active.is_(True),
        or_(Promotion.valid_until.is_(None), Promotion.valid_until > now),
    )
    return list(db.scalars(stmt))


@router.get("/promotions/{promotion_id}", response_model=PromotionOut)
def get_promotion(promotion_id: int, db: Session = Depends(get_db)):
    promo = db.get(Promotion, promotion_id)
    if promo is None or not promo.active:
        raise HTTPException(404, "Promoción no encontrada")
    return promo


@router.post("/promotions/{promotion_id}/redeem", response_model=RedemptionOut, status_code=201)
def redeem_promotion(
    promotion_id: int,
    db: Session = Depends(get_db),
    customer: BankCustomer = Depends(require_scope("promotions:redeem")),
):
    """Canjea una promoción para la cuenta del cliente autenticado (un solo uso)."""
    account = db.scalar(select(Account).where(Account.customer_id == customer.id))
    if account is None:
        raise HTTPException(404, "Cuenta no encontrada")
    if account.status == "frozen":
        raise HTTPException(403, "Cuenta congelada")

    promo = db.get(Promotion, promotion_id)
    if promo is None:
        raise HTTPException(404, "Promoción no encontrada")
    if not promo.active or (promo.valid_until is not None and promo.valid_until <= utcnow()):
        raise HTTPException(400, "Promoción vencida")

    existing = db.scalar(
        select(PromotionRedemption).where(
            PromotionRedemption.promotion_id == promo.id,
            PromotionRedemption.account_id == account.id,
        )
    )
    if existing is not None:
        raise HTTPException(409, "Promoción ya canjeada")

    redemption = PromotionRedemption(promotion_id=promo.id, account_id=account.id)
    db.add(redemption)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Promoción ya canjeada")

    db.refresh(redemption)
    return redemption