from fastapi import HTTPException
from sqlalchemy import delete, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from shared.timeutil import utcnow
from store_service.models import Coupon, CouponRedemption, Order, Product

MAX_QTY_PER_PRODUCT = 20
# Mismo mensaje para inexistente, vencido, agotado, ya usado o compra insuficiente:
# así nadie puede descubrir qué códigos existen.
INVALID_COUPON = "Cupón no válido"
COUPON_UNAVAILABLE = "El cupón ya no está disponible"


def normalize_code(code: str) -> str:
    return code.strip().upper()


def _load_valid_coupon(db: Session, code: str, user_id: str, subtotal: int) -> Coupon:
    coupon = db.get(Coupon, normalize_code(code))
    if (
        coupon is None
        or not coupon.active
        or (coupon.expires_at is not None and coupon.expires_at <= utcnow())
        or (coupon.max_uses is not None and coupon.used_count >= coupon.max_uses)
        or subtotal < coupon.min_purchase_cents
    ):
        raise HTTPException(400, INVALID_COUPON)
    already_used = db.scalar(
        select(CouponRedemption.id).where(
            CouponRedemption.coupon_code == coupon.code, CouponRedemption.user_id == user_id
        )
    )
    if already_used:
        raise HTTPException(400, INVALID_COUPON)
    return coupon


def compute_quote(db: Session, items, coupon_code: str | None, user_id: str) -> dict:
    """Calcula precios, descuento y total. Todo en centavos enteros y siempre en el servidor."""
    # Si un producto viene repetido, se suman las cantidades antes de validar existencias.
    quantities: dict[int, int] = {}
    for item in items:
        quantities[item.product_id] = quantities.get(item.product_id, 0) + item.quantity

    lines = []
    subtotal = 0
    for product_id, quantity in quantities.items():
        if quantity > MAX_QTY_PER_PRODUCT:
            raise HTTPException(400, f"Cantidad máxima por producto: {MAX_QTY_PER_PRODUCT}")
        product = db.get(Product, product_id)
        if product is None:
            raise HTTPException(404, f"Producto {product_id} no existe")
        if product.stock < quantity:
            raise HTTPException(409, f"Sin existencias de {product.name}")
        line_total = product.price_cents * quantity
        subtotal += line_total
        lines.append(
            {
                "product_id": product.id,
                "name": product.name,
                "quantity": quantity,
                "unit_price_cents": product.price_cents,
                "line_total_cents": line_total,
            }
        )

    discount = 0
    applied_code = None
    if coupon_code:
        coupon = _load_valid_coupon(db, coupon_code, user_id, subtotal)
        if coupon.kind == "percent":
            discount = subtotal * coupon.value // 100
        else:
            discount = coupon.value
        # El descuento nunca deja la orden en $0 (el pago firmado no está pensado para eso).
        discount = max(0, min(discount, subtotal - 1))
        applied_code = coupon.code

    return {
        "items": lines,
        "subtotal_cents": subtotal,
        "discount_cents": discount,
        "total_cents": subtotal - discount,
        "coupon_code": applied_code,
        "currency": "MXN",
    }


def reserve_coupon(db: Session, order: Order, user_id: str) -> None:
    """Consume un uso del cupón de forma atómica ANTES de cobrar.

    El UPDATE condicional evita que dos pagos simultáneos superen max_uses, y la
    restricción única impide que el mismo usuario lo canjee dos veces.
    """
    code = order.coupon_code
    result = db.execute(
        update(Coupon)
        .where(
            Coupon.code == code,
            Coupon.active.is_(True),
            or_(Coupon.max_uses.is_(None), Coupon.used_count < Coupon.max_uses),
            or_(Coupon.expires_at.is_(None), Coupon.expires_at > utcnow()),
        )
        .values(used_count=Coupon.used_count + 1)
    )
    if result.rowcount != 1:
        db.rollback()
        raise HTTPException(409, COUPON_UNAVAILABLE)
    db.add(CouponRedemption(coupon_code=code, user_id=user_id, order_id=order.order_id))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, COUPON_UNAVAILABLE)


def release_coupon(db: Session, order: Order) -> None:
    """Devuelve el uso del cupón si el pago no se completó."""
    db.rollback()
    code, order_id = order.coupon_code, order.order_id
    deleted = db.execute(delete(CouponRedemption).where(CouponRedemption.order_id == order_id))
    if deleted.rowcount:
        db.execute(update(Coupon).where(Coupon.code == code).values(used_count=Coupon.used_count - 1))
    db.commit()