from pathlib import Path
import httpx

from shared.config import settings


def _resolve_cert_path(rel_path: str) -> str:
    """Resuelve la ruta del certificado buscando en el cwd o relativo a la carpeta backend/."""
    path = Path(rel_path)
    if path.is_file():
        return str(path.resolve())
    backend_path = Path(__file__).resolve().parents[1] / rel_path
    if backend_path.is_file():
        return str(backend_path.resolve())
    return rel_path


def _post_bank(path: str, payload: dict) -> httpx.Response:
    kwargs = {
        "json": payload,
        "headers": {"X-API-Key": settings.bank_api_key},
        "timeout": 10,
    }
    if settings.bank_url.startswith("https://"):
        kwargs["verify"] = _resolve_cert_path(settings.mtls_ca_cert)
        kwargs["cert"] = (
            _resolve_cert_path(settings.mtls_store_cert),
            _resolve_cert_path(settings.mtls_store_key),
        )
    return httpx.post(f"{settings.bank_url}{path}", **kwargs)


def process_payment(payload: dict) -> httpx.Response:
    """Envía la orden firmada al Banco usando mTLS si BANK_URL es https."""
    return _post_bank("/transactions/process", payload)


def redeem_tickets(payload: dict) -> httpx.Response:
    """Envía los tickets firmados al Banco usando mTLS si BANK_URL es https."""
    return _post_bank("/tickets/redeem", payload)