from datetime import datetime

from sqlalchemy import Boolean, DateTime, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from shared.timeutil import utcnow
from store_service.database import Base


class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100))
    description: Mapped[str] = mapped_column(String(300))
    price_cents: Mapped[int] = mapped_column(Integer)
    stock: Mapped[int] = mapped_column(Integer, default=0)


class Coupon(Base):
    __tablename__ = "coupons"

    code: Mapped[str] = mapped_column(String(32), primary_key=True)  # siempre en mayúsculas
    kind: Mapped[str] = mapped_column(String(10))  # percent | fixed
    value: Mapped[int] = mapped_column(Integer)  # percent: 1-100 | fixed: centavos
    min_purchase_cents: Mapped[int] = mapped_column(Integer, default=0)
    max_uses: Mapped[int | None] = mapped_column(Integer, nullable=True)
    used_count: Mapped[int] = mapped_column(Integer, default=0)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class CouponRedemption(Base):
    __tablename__ = "coupon_redemptions"
    # Un usuario solo puede canjear un cupón una vez; lo garantiza la base de datos.
    __table_args__ = (UniqueConstraint("coupon_code", "user_id", name="uq_redemption_user_coupon"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    coupon_code: Mapped[str] = mapped_column(String(32))
    user_id: Mapped[str] = mapped_column(String(64))
    order_id: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (Index("ix_orders_user_id", "user_id"),)

    order_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64))
    items_json: Mapped[str] = mapped_column(Text)
    subtotal_cents: Mapped[int] = mapped_column(Integer, default=0)
    discount_cents: Mapped[int] = mapped_column(Integer, default=0)
    coupon_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    total_cents: Mapped[int] = mapped_column(Integer)  # lo que realmente se cobra
    currency: Mapped[str] = mapped_column(String(3), default="MXN")
    status: Mapped[str] = mapped_column(String(20), default="pending")  # pending | paid
    receipt_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    receipt_signature: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)