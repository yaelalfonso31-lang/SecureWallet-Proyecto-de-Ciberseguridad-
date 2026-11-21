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


def process_payment(payload: dict) -> httpx.Response:
    """Envía la orden firmada al Banco. Si BANK_URL es https, usa mTLS con los certificados configurados."""
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

    return httpx.post(
        f"{settings.bank_url}/transactions/process",
        **kwargs,
    )

def redeem_tickets(payload: dict) -> httpx.Response:
    """Envía los tickets firmados al Banco para confirmar su validez y evitar doble gasto."""
    return httpx.post(
        f"{settings.bank_url}/tickets/redeem",
        json=payload,
        headers={"X-API-Key": settings.bank_api_key},
        timeout=10,
    )