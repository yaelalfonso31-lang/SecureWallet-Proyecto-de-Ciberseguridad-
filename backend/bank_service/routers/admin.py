"""Administración de promociones del Banco (B6). Solo para clientes con rol `admin`.

El rol se lee de la base de datos (no del token), así que quitar el rol surte efecto de inmediato.
"""
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from bank_service.database import get_db
from bank_service.deps import require_admin
from bank_service.models import BankCustomer, Promotion

router = APIRouter(prefix="/admin", tags=["admin"])


class PromotionAdminOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str
    discount_percent: int
    active: bool
    valid_until: datetime | None = None


class PromotionCreate(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    description: str = Field(min_length=1, max_length=300)
    discount_percent: int = Field(ge=1, le=100)
    active: bool = True
    valid_until: datetime | None = None


class PromotionPatch(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=100)
    description: str | None = Field(default=None, min_length=1, max_length=300)
    discount_percent: int | None = Field(default=None, ge=1, le=100)
    active: bool | None = None
    valid_until: datetime | None = None


@router.get("/promotions", response_model=list[PromotionAdminOut])
def list_all_promotions(
    db: Session = Depends(get_db),
    admin: BankCustomer = Depends(require_admin),
):
    """Todas las promociones, incluidas las inactivas y las vencidas."""
    return list(db.scalars(select(Promotion).order_by(Promotion.id)))


@router.post("/promotions", response_model=PromotionAdminOut, status_code=201)
def create_promotion(
    body: PromotionCreate,
    db: Session = Depends(get_db),
    admin: BankCustomer = Depends(require_admin),
):
    promotion = Promotion(**body.model_dump())
    db.add(promotion)
    db.commit()
    db.refresh(promotion)
    return promotion


@router.patch("/promotions/{promotion_id}", response_model=PromotionAdminOut)
def patch_promotion(
    promotion_id: int,
    body: PromotionPatch,
    db: Session = Depends(get_db),
    admin: BankCustomer = Depends(require_admin),
):
    promotion = db.get(Promotion, promotion_id)
    if promotion is None:
        raise HTTPException(404, "Promoción no encontrada")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(promotion, field, value)
    db.commit()
    db.refresh(promotion)
    return promotion
