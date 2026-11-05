import re
import secrets

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from shared.security.crypto import encrypt
from shared.timeutil import utcnow
from shared.validators import detect_brand, luhn_valid
from wallet_service.audit import log_event
from wallet_service.database import get_db
from wallet_service.deps import get_current_user
from wallet_service.models import Card, User
from wallet_service.schemas import CardIn, CardOut

router = APIRouter(prefix="/cards", tags=["cards"])


@router.post("", response_model=CardOut, status_code=201)
def add_card(body: CardIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    number = re.sub(r"[ -]", "", body.number)
    if not (number.isdigit() and 13 <= len(number) <= 19 and luhn_valid(number)):
        raise HTTPException(422, "Número de tarjeta inválido")

    now = utcnow()
    if (body.exp_year, body.exp_month) < (now.year, now.month):
        raise HTTPException(422, "La tarjeta está vencida")

    card = Card(
        user_id=user.id,
        token="tok_" + secrets.token_hex(12),
        brand=detect_brand(number),
        last4=number[-4:],
        holder_name=body.holder_name.strip(),
        exp_month=body.exp_month,
        exp_year=body.exp_year,
        pan_encrypted=encrypt(number, aad=user.id),  # AES-256-GCM ligado al dueño
    )
    db.add(card)
    db.commit()
    db.refresh(card)
    log_event(db, "card_added", user.id, detail=f"last4={card.last4}")
    return card


@router.get("", response_model=list[CardOut])
def list_cards(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return list(db.scalars(select(Card).where(Card.user_id == user.id)))


@router.delete("/{card_id}", status_code=204)
def delete_card(card_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    card = db.get(Card, card_id)
    if card is None or card.user_id != user.id:
        raise HTTPException(404, "Tarjeta no encontrada")
    db.delete(card)
    db.commit()
    log_event(db, "card_deleted", user.id, detail=f"last4={card.last4}")
