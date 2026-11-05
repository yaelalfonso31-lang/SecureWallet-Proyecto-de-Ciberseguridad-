import secrets
import time

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from shared.config import settings
from shared.schemas import PaymentOrder, SignedOrder
from shared.security.signing import sign
from wallet_service.audit import log_event
from wallet_service.database import get_db
from wallet_service.deps import get_current_user
from wallet_service.models import Card, User
from wallet_service.schemas import PaymentRequest

router = APIRouter(prefix="/payments", tags=["payments"])


@router.post("/authorize", response_model=SignedOrder)
def authorize(body: PaymentRequest, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """La Wallet firma la orden de pago. El Banco verificará esta firma.

    TODO equipo Wallet: exigir re-autenticación (PIN/biometría/TOTP) antes de firmar.
    """
    card_token = None
    if body.card_id:
        card = db.get(Card, body.card_id)
        if card is None or card.user_id != user.id:
            raise HTTPException(404, "Tarjeta no encontrada")
        card_token = card.token

    order = PaymentOrder(
        order_id=body.order_id,
        merchant=body.merchant,
        amount_cents=body.amount_cents,
        currency=body.currency,
        payer=user.id,
        card_token=card_token,
        nonce=secrets.token_hex(16),
        timestamp=int(time.time()),
    )
    signature = sign(settings.wallet_signing_private_key, order.model_dump())
    log_event(db, "payment_authorized", user.id, detail=f"order={order.order_id}")
    return SignedOrder(order=order, signature=signature)
