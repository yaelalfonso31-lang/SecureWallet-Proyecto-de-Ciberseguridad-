from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.orm import Session

from bank_service.database import get_db
from bank_service.models import Promotion

router = APIRouter(tags=["promotions"])


class PromotionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str
    discount_percent: int


@router.get("/promotions", response_model=list[PromotionOut])
def list_promotions(db: Session = Depends(get_db)):
    return list(db.scalars(select(Promotion).where(Promotion.active.is_(True))))
