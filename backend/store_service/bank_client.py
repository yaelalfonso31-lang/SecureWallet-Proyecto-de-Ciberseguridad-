import httpx

from shared.config import settings


def process_payment(payload: dict) -> httpx.Response:
    """Envía la orden firmada al Banco. Se aísla aquí para poder simularlo en las pruebas."""
    return httpx.post(
        f"{settings.bank_url}/transactions/process",
        json=payload,
        headers={"X-API-Key": settings.bank_api_key},
        timeout=10,
    )

def redeem_tickets(payload: dict) -> httpx.Response:
    """Envía los tickets firmados al Banco para confirmar su validez y evitar doble gasto."""
    return httpx.post(
        f"{settings.bank_url}/tickets/redeem",
        json=payload,
        headers={"X-API-Key": settings.bank_api_key},
        timeout=10,
    )