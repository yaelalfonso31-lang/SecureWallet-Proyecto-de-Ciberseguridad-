"""Verificaciones compartidas de órdenes y comprobantes firmados.

Extraídas de `process_transaction` en B5 para reutilizarlas también en las
transferencias banco <-> wallet.
"""
import time

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from shared.config import settings
from shared.security.signing import verify


def verify_wallet_signature(payload: dict, signature: str) -> None:
    """Autenticidad e integridad: la firma debe ser de la Wallet y el contenido no pudo cambiar."""
    if not verify(settings.wallet_signing_public_key, payload, signature):
        raise HTTPException(400, "Firma inválida")


def ensure_fresh(timestamp: int) -> None:
    """Frescura: rechaza comprobantes viejos (ventana corta anti-replay)."""
    if abs(time.time() - timestamp) > settings.order_max_age_seconds:
        raise HTTPException(400, "Comprobante expirado")


def ensure_nonce_unique(db: Session, model, nonce: str) -> None:
    """Unicidad: el mismo nonce no se procesa dos veces (anti-replay)."""
    if db.scalar(select(model).where(model.nonce == nonce)):
        raise HTTPException(409, "Nonce ya utilizado")
