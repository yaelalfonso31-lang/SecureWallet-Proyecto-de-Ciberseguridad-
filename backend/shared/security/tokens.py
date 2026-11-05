from datetime import datetime, timedelta, timezone

import jwt

from shared.config import settings


def create_access_token(subject: str, extra: dict | None = None) -> str:
    if not settings.jwt_secret:
        raise RuntimeError("JWT_SECRET no está configurada (ver scripts/generate_env.py)")
    now = datetime.now(timezone.utc)
    payload = {
        "sub": subject,
        "iat": now,
        "exp": now + timedelta(minutes=settings.access_token_minutes),
        **(extra or {}),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict:
    """Lanza jwt.PyJWTError si el token es inválido o expiró."""
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
