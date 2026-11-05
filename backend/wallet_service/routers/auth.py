from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from shared.config import settings
from shared.security.passwords import hash_password, verify_password
from shared.security.tokens import create_access_token
from shared.timeutil import utcnow
from wallet_service.audit import log_event
from wallet_service.database import get_db
from wallet_service.deps import get_current_user
from wallet_service.models import User
from wallet_service.schemas import LoginIn, RegisterIn, TokenOut, UserOut

router = APIRouter(prefix="/auth", tags=["auth"])

# Hash ficticio para igualar tiempos de respuesta cuando el correo no existe.
_DUMMY_HASH = hash_password("contraseña-ficticia-1")
_INVALID = "Credenciales inválidas"


@router.post("/register", response_model=UserOut, status_code=201)
def register(body: RegisterIn, db: Session = Depends(get_db)):
    email = body.email.lower()
    if db.scalar(select(User).where(User.email == email)):
        # Mensaje genérico para no revelar qué correos existen.
        raise HTTPException(409, "No fue posible completar el registro")
    user = User(
        email=email,
        full_name=body.full_name.strip(),
        password_hash=hash_password(body.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    log_event(db, "register", user.id)
    return user


@router.post("/login", response_model=TokenOut)
def login(body: LoginIn, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == body.email.lower()))

    if user is None:
        verify_password(_DUMMY_HASH, body.password)
        raise HTTPException(401, _INVALID)

    if user.locked_until and user.locked_until > utcnow():
        log_event(db, "login_blocked", user.id)
        raise HTTPException(423, "Cuenta bloqueada temporalmente. Intenta más tarde.")

    if not verify_password(user.password_hash, body.password):
        user.failed_attempts += 1
        if user.failed_attempts >= settings.max_failed_logins:
            user.locked_until = utcnow() + timedelta(minutes=settings.lockout_minutes)
            user.failed_attempts = 0
            log_event(db, "account_locked", user.id)
        db.commit()
        log_event(db, "login_failed", user.id)
        raise HTTPException(401, _INVALID)

    user.failed_attempts = 0
    user.locked_until = None
    db.commit()
    log_event(db, "login_ok", user.id)
    return TokenOut(access_token=create_access_token(user.id))


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return user
