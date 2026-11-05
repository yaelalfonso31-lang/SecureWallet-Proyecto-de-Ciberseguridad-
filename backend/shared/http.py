from fastapi import FastAPI
from starlette.middleware.base import BaseHTTPMiddleware


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
    """Aplica cabeceras de seguridad. TODO equipo: rate limiting (slowapi) y CORS restrictivo."""
    app.add_middleware(SecurityHeadersMiddleware)
