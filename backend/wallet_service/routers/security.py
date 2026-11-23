"""Centro de seguridad de la Wallet: 2FA (TOTP RFC 6238) y bitácora SHA-256 verificable."""
from datetime import datetime

import pyotp
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from wallet_service.audit import log_event, verify_chain
from wallet_service.database import get_db
from wallet_service.deps import get_current_user
from wallet_service.models import AuditLog, User
from wallet_service.schemas import TotpCodeIn, TotpSetupOut

router = APIRouter(prefix="/security", tags=["security"])


class AuditEntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    event: str
    detail: str
    prev_hash: str
    hash: str
    created_at: datetime


class AuditChainOut(BaseModel):
    chain_valid: bool
    total_records: int
    entries: list[AuditEntryOut]


@router.get("/audit", response_model=AuditChainOut)
def get_audit_log(
    limit: int = Query(30, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Devuelve la bitácora del usuario y verifica la integridad SHA-256 de toda la cadena."""
    is_valid = verify_chain(db)
    total = db.scalar(select(func.count(AuditLog.id))) or 0
    rows = list(
        db.scalars(
            select(AuditLog)
            .where(AuditLog.user_id == user.id)
            .order_by(AuditLog.id.desc())
            .limit(limit)
        )
    )
    return AuditChainOut(chain_valid=is_valid, total_records=total, entries=rows)


@router.post("/2fa/setup", response_model=TotpSetupOut)
def setup_2fa(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Genera un secreto TOTP base32 y su URI otpauth:// para Google Authenticator / Authy."""
    secret = pyotp.random_base32()
    user.totp_secret = secret
    user.totp_enabled = False
    db.commit()
    log_event(db, "totp_setup_started", user.id)
    uri = pyotp.TOTP(secret).provisioning_uri(name=user.email, issuer_name="SecureWallet")
    return TotpSetupOut(secret=secret, provisioning_uri=uri)


@router.post("/2fa/enable")
def enable_2fa(body: TotpCodeIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Confirma el primer código de 6 dígitos y activa el 2FA en la cuenta."""
    if not user.totp_secret:
        raise HTTPException(400, "Primero inicia la configuración 2FA en /security/2fa/setup")
    if not pyotp.TOTP(user.totp_secret).verify(body.code.strip(), valid_window=1):
        raise HTTPException(400, "Código 2FA inválido")
    user.totp_enabled = True
    db.commit()
    log_event(db, "totp_enabled", user.id)
    return {"totp_enabled": True}


@router.post("/2fa/disable")
def disable_2fa(body: TotpCodeIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Desactiva el 2FA exigiendo un código TOTP válido."""
    if not user.totp_enabled or not user.totp_secret:
        raise HTTPException(400, "El 2FA no está activo")
    if not pyotp.TOTP(user.totp_secret).verify(body.code.strip(), valid_window=1):
        raise HTTPException(400, "Código 2FA inválido")
    user.totp_enabled = False
    user.totp_secret = None
    db.commit()
    log_event(db, "totp_disabled", user.id)
    return {"totp_enabled": False}