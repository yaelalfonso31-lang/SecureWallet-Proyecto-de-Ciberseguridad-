import threading
import time
from collections import defaultdict, deque

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from shared.config import settings

_REQUEST_LOG: dict[str, deque[float]] = defaultdict(deque)
_LOCK = threading.Lock()


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Limita peticiones por IP en ventana deslizante de 60 s contra fuerza bruta y DoS."""

    async def dispatch(self, request, call_next):
        limit = settings.rate_limit_per_minute
        if limit > 0:
            client_ip = f"{id(self)}:{request.client.host if request.client else 'unknown'}"
            now = time.monotonic()
            cutoff = now - 60.0
            with _LOCK:
                timestamps = _REQUEST_LOG[client_ip]
                while timestamps and timestamps[0] <= cutoff:
                    timestamps.popleft()
                if len(timestamps) >= limit:
                    return JSONResponse(
                        status_code=429,
                        content={"detail": "Demasiadas peticiones. Intenta más tarde."},
                        headers={"Retry-After": "60"},
                    )
                timestamps.append(now)
        return await call_next(request)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
        return response


def harden_app(app: FastAPI) -> None:
    """Aplica cabeceras de seguridad, rate limiting por IP y CORS restrictivo."""
    origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type", "X-API-Key", "X-Admin-Key"],
    )
    app.add_middleware(RateLimitMiddleware)
    app.add_middleware(SecurityHeadersMiddleware)