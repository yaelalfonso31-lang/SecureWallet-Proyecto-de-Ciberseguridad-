"""Contratos compartidos entre Wallet, Banco y Tienda."""
from pydantic import BaseModel, ConfigDict, Field


class PaymentOrder(BaseModel):
    """Orden de pago que firma la Wallet y valida el Banco."""

    model_config = ConfigDict(extra="forbid")

    order_id: str = Field(min_length=1, max_length=64)
    merchant: str = Field(min_length=1, max_length=100)
    amount_cents: int = Field(gt=0, le=100_000_000)
    currency: str = Field(default="MXN", pattern=r"^[A-Z]{3}$")
    payer: str = Field(min_length=1, max_length=64)
    card_token: str | None = None
    nonce: str = Field(min_length=16, max_length=64)  # anti-replay
    timestamp: int  # epoch en segundos (anti-replay)


class SignedOrder(BaseModel):
    order: PaymentOrder
    signature: str


class SignedReceipt(BaseModel):
    receipt: dict
    signature: str
