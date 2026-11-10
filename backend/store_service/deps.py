import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from shared.security.tokens import decode_access_token

bearer = HTTPBearer(auto_error=False)


def current_user_id(creds: HTTPAuthorizationCredentials | None = Depends(bearer)) -> str:
    """Valida el JWT emitido por la Wallet y devuelve el id del usuario (claim 'sub')."""
    unauthorized = HTTPException(401, "No autenticado", headers={"WWW-Authenticate": "Bearer"})
    if creds is None:
        raise unauthorized
    try:
        payload = decode_access_token(creds.credentials)
    except jwt.PyJWTError:
        raise unauthorized
    sub = payload.get("sub")
    if not sub:
        raise unauthorized
    return str(sub)