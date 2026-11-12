import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from bank_service.database import Base
from shared.timeutil import utcnow


def _uuid() -> str:
    return uuid.uuid4().hex


class BankCustomer(Base):
    """Cliente del Banco. Puede ser `customer` o `admin`.

    Es la identidad propia del Banco, distinta del usuario de la Wallet.
    """

    __tablename__ = "bank_customers"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    failed_attempts: Mapped[int] = mapped_column(Integer, default=0)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    role: Mapped[str] = mapped_column(String(20), default="customer")  # customer | admin
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Account(Base):
    __tablename__ = "accounts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    owner_ref: Mapped[str] = mapped_column(String(64), unique=True, index=True)  # id del usuario en la Wallet
    customer_id: Mapped[str | None] = mapped_column(ForeignKey("bank_customers.id"), nullable=True, index=True)
    account_number: Mapped[str | None] = mapped_column(String(20), unique=True, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="active")  # active | frozen
    balance_cents: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Movement(Base):
    """Movimiento inmutable de una cuenta (cargo o abono). Da trazabilidad."""

    __tablename__ = "movements"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id"), index=True)
    kind: Mapped[str] = mapped_column(String(10))  # debit | credit
    amount_cents: Mapped[int] = mapped_column(Integer)
    balance_after_cents: Mapped[int] = mapped_column(Integer)
    concept: Mapped[str] = mapped_column(String(200), default="")
    reference: Mapped[str] = mapped_column(String(64), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class AuthorizationCode(Base):
    """Código de autorización OAuth2 + PKCE (un solo uso, vida corta)."""

    __tablename__ = "authorization_codes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    code_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    code_challenge: Mapped[str] = mapped_column(String(128))
    customer_id: Mapped[str] = mapped_column(ForeignKey("bank_customers.id"), index=True)
    wallet_user_id: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    used: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Promotion(Base):
    __tablename__ = "promotions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(100))
    description: Mapped[str] = mapped_column(String(300))
    discount_percent: Mapped[int] = mapped_column(Integer)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    valid_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class PromotionRedemption(Base):
    """Canje de una promoción por una cuenta. De un solo uso."""

    __tablename__ = "promotion_redemptions"
    __table_args__ = (
        UniqueConstraint("promotion_id", "account_id", name="uq_redemption_promotion_account"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    promotion_id: Mapped[int] = mapped_column(ForeignKey("promotions.id"), index=True)
    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id"), index=True)
    redeemed_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    used_in_order_id: Mapped[str | None] = mapped_column(String(64), nullable=True)


class Transfer(Base):
    """Transferencia banco <-> wallet, con idempotencia y nonce anti-replay."""

    __tablename__ = "transfers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    transfer_id: Mapped[str] = mapped_column(String(32), unique=True, index=True, default=_uuid)
    nonce: Mapped[str] = mapped_column(String(64), unique=True)
    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id"), index=True)
    direction: Mapped[str] = mapped_column(String(20))  # to_wallet | from_wallet
    amount_cents: Mapped[int] = mapped_column(Integer)
    idempotency_key: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    # Comprobante y firma guardados para poder devolver el MISMO comprobante
    # cuando se repite la idempotency_key (idempotencia exacta).
    voucher_json: Mapped[str] = mapped_column(Text, default="")
    signature: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ProcessedOrder(Base):
    """Órdenes ya procesadas. Los UNIQUE de order_id y nonce evitan ataques de repetición (replay)."""

    __tablename__ = "processed_orders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id: Mapped[str] = mapped_column(String(64), unique=True)
    nonce: Mapped[str] = mapped_column(String(64), unique=True)
    payer: Mapped[str] = mapped_column(String(64))
    amount_cents: Mapped[int] = mapped_column(Integer)
    receipt_json: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
