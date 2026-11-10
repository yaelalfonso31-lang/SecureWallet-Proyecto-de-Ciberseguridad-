"""Autenticación y autorización del Banco.

El Banco emite sus propios JWT, firmados con `BANK_JWT_SECRET` y con `aud="bank"`,
independientes de los tokens de la Wallet. Estas dependencias son el contrato que
comparten las dos personas del equipo Banco (definido en B0).
"""
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from bank_service.database import get_db
from bank_service.models import BankCustomer
from shared.config import settings

bearer = HTTPBearer(auto_error=False)

BANK_TOKEN_AUDIENCE = "bank"

# Scopes que puede tener un token del Banco. El fixture de pruebas los concede todos.
ALL_SCOPES = (
    "accounts:read",
    "promotions:read",
    "promotions:redeem",
    "transfers:write",
)


def create_bank_token(customer_id: str, scopes=ALL_SCOPES) -> str:
    """Emite un JWT del Banco para un cliente, con `aud="bank"` y los scopes dados."""
    if not settings.bank_jwt_secret:
        raise RuntimeError("BANK_JWT_SECRET no está configurada (ver scripts/generate_env.py)")
    now = datetime.now(timezone.utc)
    payload = {
        "sub": customer_id,
        "aud": BANK_TOKEN_AUDIENCE,
        "scope": " ".join(scopes),
        "iat": now,
        "exp": now + timedelta(minutes=settings.access_token_minutes),
    }
    return jwt.encode(payload, settings.bank_jwt_secret, algorithm=settings.jwt_algorithm)


def _decode_bank_token(token: str) -> dict:
    """Valida firma, expiración y `aud="bank"`. Lanza jwt.PyJWTError si falla."""
    return jwt.decode(
        token,
        settings.bank_jwt_secret,
        algorithms=[settings.jwt_algorithm],
        audience=BANK_TOKEN_AUDIENCE,
    )


def _get_payload(creds: HTTPAuthorizationCredentials | None) -> dict:
    unauthorized = HTTPException(status.HTTP_401_UNAUTHORIZED, "No autenticado")
    if creds is None:
        raise unauthorized
    try:
        return _decode_bank_token(creds.credentials)
    except jwt.PyJWTError:
        raise unauthorized


def _customer_from_payload(payload: dict, db: Session) -> BankCustomer:
    customer = db.get(BankCustomer, payload.get("sub"))
    if customer is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "No autenticado")
    return customer


def get_current_customer(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> BankCustomer:
    """Devuelve el cliente dueño del token (cargado desde la BD)."""
    return _customer_from_payload(_get_payload(creds), db)


def require_scope(scope: str):
    """Fábrica de dependencias: exige que el token incluya `scope`."""

    def dependency(
        creds: HTTPAuthorizationCredentials | None = Depends(bearer),
        db: Session = Depends(get_db),
    ) -> BankCustomer:
        payload = _get_payload(creds)
        if scope not in payload.get("scope", "").split():
            raise HTTPException(status.HTTP_403_FORBIDDEN, f"Scope requerido: {scope}")
        return _customer_from_payload(payload, db)

    return dependency


def require_admin(customer: BankCustomer = Depends(get_current_customer)) -> BankCustomer:
    """Exige rol admin. El rol se lee de la BD (vía get_current_customer), no del token."""
    if customer.role != "admin":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Se requiere rol de administrador")
    return customer
