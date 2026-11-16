import secrets
import time

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from shared.config import settings
from shared.security.signing import sign
from wallet_service.audit import log_event
from wallet_service.database import get_db
from wallet_service.deps import get_current_user
from wallet_service.models import User
from wallet_service.schemas import BankLinkAssertionOut, BankLinkAssertionPayload

router = APIRouter(prefix="/bank-link", tags=["bank-link"])


@router.post("/assertion", response_model=BankLinkAssertionOut)
def create_bank_link_assertion(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Firma una aserción de identidad Ed25519 para vincular la cuenta en el Banco (B2)."""
    assertion = BankLinkAssertionPayload(
        wallet_user_id=user.id,
        nonce=secrets.token_hex(16),
        timestamp=int(time.time()),
        audience="bank",
    )
    signature = sign(settings.wallet_signing_private_key, assertion.model_dump())
    log_event(db, "bank_link_assertion", user.id)
    return BankLinkAssertionOut(assertion=assertion, signature=signature)