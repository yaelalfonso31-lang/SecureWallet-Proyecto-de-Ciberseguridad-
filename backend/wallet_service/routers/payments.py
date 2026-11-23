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
import pyotp

router = APIRouter(prefix="/payments", tags=["payments"])


@router.post("/authorize", response_model=SignedOrder)
def authorize(body: PaymentRequest, user: User = Depends(get_current_user), db: Session = Depends(get_db)):

    card_token = None
    if body.card_id:
        card = db.get(Card, body.card_id)
        if card is None or card.user_id != user.id:
            raise HTTPException(404, "Tarjeta no encontrada")
        card_token = card.token

    if user.totp_enabled:
        if not body.totp_code or not user.totp_secret:
            raise HTTPException(403, "Se requiere código 2FA (TOTP) para autorizar el pago")
        if not pyotp.TOTP(user.totp_secret).verify(body.totp_code.strip(), valid_window=1):
            raise HTTPException(403, "Código 2FA (TOTP) inválido")

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
