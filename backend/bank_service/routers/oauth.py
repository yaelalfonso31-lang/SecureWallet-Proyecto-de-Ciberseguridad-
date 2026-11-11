"""Vinculación Wallet <-> Banco con OAuth2 Authorization Code + PKCE (B2).

Flujo:
1. La app pide a la Wallet una aserción firmada con el id de su usuario.
2. `POST /oauth/authorize`: el cliente del Banco se autentica con su contraseña y
   envía el `code_challenge` (S256) y la aserción. El Banco devuelve un código de un
   solo uso y vida corta.
3. `POST /oauth/token`: la app canjea el código junto con el `code_verifier`. Si
   coincide con el challenge, se liga la cuenta al usuario de la Wallet y se emite
   el token del Banco.
"""
import base64
import hashlib
import secrets
import time
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from bank_service.database import get_db
from bank_service.deps import ALL_SCOPES, create_bank_token
from bank_service.models import Account, AuthorizationCode, BankCustomer
from shared.config import settings
from shared.security.hashing import constant_time_equals, sha256_hex
from shared.security.passwords import hash_password, verify_password
from shared.security.signing import verify
from shared.timeutil import utcnow

router = APIRouter(prefix="/oauth", tags=["oauth"])

# Apps registradas que pueden pedir códigos. Son clientes públicos (sin secreto): PKCE los protege.
ALLOWED_CLIENT_IDS = frozenset({"securewallet-mobile"})
AUTH_CODE_TTL_SECONDS = 60
ASSERTION_AUDIENCE = "bank"

# Hash ficticio para igualar tiempos de respuesta cuando el correo no existe.
_DUMMY_HASH = hash_password("contraseña-ficticia-1")
_INVALID_CREDENTIALS = "Credenciales inválidas"
_INVALID_CODE = "Código de autorización inválido"

# RFC 7636: verifier de 43 a 128 caracteres "unreserved"; el challenge S256 siempre mide 43.
_PKCE_VERIFIER_PATTERN = r"^[A-Za-z0-9\-._~]{43,128}$"
_PKCE_CHALLENGE_PATTERN = r"^[A-Za-z0-9\-_]{43}$"


class WalletAssertionPayload(BaseModel):
    """Datos que firma la Wallet para probar quién es su usuario."""

    model_config = ConfigDict(extra="forbid")

    wallet_user_id: str = Field(min_length=1, max_length=64)
    nonce: str = Field(min_length=16, max_length=64)
    timestamp: int  # epoch en segundos
    audience: str = Field(max_length=20)


class WalletAssertion(BaseModel):
    assertion: WalletAssertionPayload
    signature: str = Field(max_length=200)


class AuthorizeIn(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=1, max_length=128)
    code_challenge: str = Field(pattern=_PKCE_CHALLENGE_PATTERN)
    code_challenge_method: str = Field(max_length=10)
    client_id: str = Field(max_length=64)
    state: str = Field(min_length=8, max_length=128)
    wallet_assertion: WalletAssertion


class AuthorizeOut(BaseModel):
    code: str
    state: str


class TokenIn(BaseModel):
    code: str = Field(min_length=1, max_length=128)
    code_verifier: str = Field(pattern=_PKCE_VERIFIER_PATTERN)
    client_id: str = Field(max_length=64)


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    scope: str


def pkce_s256(code_verifier: str) -> str:
    """BASE64URL(SHA256(verifier)) sin relleno, como define RFC 7636."""
    digest = hashlib.sha256(code_verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def _verify_assertion(body: WalletAssertion) -> str:
    """Valida la aserción de la Wallet y devuelve el `wallet_user_id` que certifica."""
    payload = body.assertion
    if not verify(settings.wallet_signing_public_key, payload.model_dump(), body.signature):
        raise HTTPException(400, "Aserción de la Wallet inválida")
    if payload.audience != ASSERTION_AUDIENCE:
        raise HTTPException(400, "Aserción de la Wallet inválida")
    if abs(time.time() - payload.timestamp) > settings.order_max_age_seconds:
        raise HTTPException(400, "Aserción de la Wallet expirada")
    return payload.wallet_user_id


def _authenticate(db: Session, email: str, password: str) -> BankCustomer:
    """Contraseña con Argon2id y bloqueo temporal tras varios intentos fallidos."""
    customer = db.scalar(select(BankCustomer).where(BankCustomer.email == email.lower()))

    if customer is None:
        verify_password(_DUMMY_HASH, password)
        raise HTTPException(400, _INVALID_CREDENTIALS)

    if customer.locked_until and customer.locked_until > utcnow():
        raise HTTPException(423, "Cuenta bloqueada temporalmente. Intenta más tarde.")

    if not verify_password(customer.password_hash, password):
        customer.failed_attempts += 1
        if customer.failed_attempts >= settings.max_failed_logins:
            customer.locked_until = utcnow() + timedelta(minutes=settings.lockout_minutes)
            customer.failed_attempts = 0
        db.commit()
        raise HTTPException(400, _INVALID_CREDENTIALS)

    customer.failed_attempts = 0
    customer.locked_until = None
    return customer


def _account_to_link(db: Session, customer_id: str, wallet_user_id: str) -> Account:
    """Cuenta del cliente que se va a ligar. Un usuario de la Wallet solo puede tener una."""
    account = db.scalar(select(Account).where(Account.customer_id == customer_id))
    if account is None:
        raise HTTPException(400, "El cliente no tiene una cuenta bancaria")
    if account.status != "active":
        raise HTTPException(403, "La cuenta no está activa")
    taken = db.scalar(
        select(Account.id).where(Account.owner_ref == wallet_user_id, Account.id != account.id)
    )
    if taken is not None:
        raise HTTPException(409, "Este usuario de la Wallet ya está vinculado a otra cuenta")
    return account


@router.post("/authorize", response_model=AuthorizeOut)
def authorize(body: AuthorizeIn, db: Session = Depends(get_db)):
    if body.client_id not in ALLOWED_CLIENT_IDS:
        raise HTTPException(400, "client_id no permitido")
    # `plain` mandaría el verifier tal cual: quien intercepte el código también lo tendría.
    if body.code_challenge_method != "S256":
        raise HTTPException(400, "Solo se acepta code_challenge_method S256")

    wallet_user_id = _verify_assertion(body.wallet_assertion)
    customer = _authenticate(db, body.email, body.password)
    _account_to_link(db, customer.id, wallet_user_id)

    # Solo se guarda el hash: una copia de la BD no sirve para canjear códigos.
    code = secrets.token_urlsafe(32)
    db.add(
        AuthorizationCode(
            code_hash=sha256_hex(code),
            code_challenge=body.code_challenge,
            customer_id=customer.id,
            wallet_user_id=wallet_user_id,
            expires_at=utcnow() + timedelta(seconds=AUTH_CODE_TTL_SECONDS),
        )
    )
    db.commit()
    return AuthorizeOut(code=code, state=body.state)


@router.post("/token", response_model=TokenOut)
def token(body: TokenIn, db: Session = Depends(get_db)):
    if body.client_id not in ALLOWED_CLIENT_IDS:
        raise HTTPException(400, "client_id no permitido")

    auth_code = db.scalar(select(AuthorizationCode).where(AuthorizationCode.code_hash == sha256_hex(body.code)))
    if auth_code is None:
        raise HTTPException(400, _INVALID_CODE)

    # Se marca como usado ANTES de verificar, de forma atómica: aunque el verifier sea
    # incorrecto, el código ya no sirve (un atacante no puede probar varios verifiers),
    # y dos canjes simultáneos no pueden ganar los dos.
    consumed = db.execute(
        update(AuthorizationCode)
        .where(AuthorizationCode.id == auth_code.id, AuthorizationCode.used.is_(False))
        .values(used=True)
    )
    db.commit()
    if consumed.rowcount != 1:
        raise HTTPException(400, _INVALID_CODE)

    if auth_code.expires_at <= utcnow():
        raise HTTPException(400, _INVALID_CODE)
    if not constant_time_equals(pkce_s256(body.code_verifier), auth_code.code_challenge):
        raise HTTPException(400, _INVALID_CODE)

    # Desde ahora, las órdenes que firme la Wallet con este `payer` se cobran de esta cuenta.
    account = _account_to_link(db, auth_code.customer_id, auth_code.wallet_user_id)
    account.owner_ref = auth_code.wallet_user_id
    db.commit()

    return TokenOut(
        access_token=create_bank_token(auth_code.customer_id, ALL_SCOPES),
        expires_in=settings.access_token_minutes * 60,
        scope=" ".join(ALL_SCOPES),
    )
