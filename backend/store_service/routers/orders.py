import json
import secrets

import httpx
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import update
from sqlalchemy.orm import Session

from shared.config import settings
from shared.schemas import SignedOrder
from shared.security.signing import verify
from store_service.bank_client import process_payment
from store_service.database import get_db
from store_service.deps import current_user_id
from store_service.models import Order, Product
from store_service.pricing import compute_quote, release_coupon, reserve_coupon
from store_service.schemas import OrderCreateIn

router = APIRouter(prefix="/orders", tags=["orders"])

MERCHANT = "SecureStore"

# Estados: pending -> processing -> paid.
# Si el pago falla vuelve a pending; si el recibo es sospechoso queda en failed (revisión manual).
PENDING, PROCESSING, PAID, FAILED = "pending", "processing", "paid", "failed"
NOT_PAYABLE = "La orden ya fue pagada o se está procesando"


class SuspectReceipt(HTTPException):
    """El Banco respondió, pero el recibo no se pudo verificar o no coincide con la compra."""


def _get_own_order(db: Session, order_id: str, user_id: str) -> Order:
    order = db.get(Order, order_id)
    # 404 (no 403) si no existe o es de otro usuario: no revela qué ids existen.
    if order is None or order.user_id != user_id:
        raise HTTPException(404, "Orden no encontrada")
    return order


@router.post("", status_code=201)
def create_order(body: OrderCreateIn, user_id: str = Depends(current_user_id), db: Session = Depends(get_db)):
    quote = compute_quote(db, body.items, body.coupon_code, user_id)
    items = [
        {"product_id": l["product_id"], "quantity": l["quantity"], "unit_price_cents": l["unit_price_cents"]}
        for l in quote["items"]
    ]
    order = Order(
        order_id="ord_" + secrets.token_hex(8),
        user_id=user_id,
        items_json=json.dumps(items),
        subtotal_cents=quote["subtotal_cents"],
        discount_cents=quote["discount_cents"],
        coupon_code=quote["coupon_code"],
        total_cents=quote["total_cents"],
    )
    db.add(order)
    db.commit()
    return {
        "order_id": order.order_id,
        "merchant": MERCHANT,
        "amount_cents": order.total_cents,
        "subtotal_cents": order.subtotal_cents,
        "discount_cents": order.discount_cents,
        "coupon_code": order.coupon_code,
        "currency": order.currency,
        "status": order.status,
    }


# ---------- helpers del pago ----------


def _set_status(db: Session, order_id: str, status: str) -> None:
    db.execute(update(Order).where(Order.order_id == order_id).values(status=status))
    db.commit()


def _claim_order(db: Session, order_id: str) -> bool:
    """pending -> processing de forma atómica. Solo una petición puede ganar."""
    result = db.execute(
        update(Order).where(Order.order_id == order_id, Order.status == PENDING).values(status=PROCESSING)
    )
    db.commit()
    return result.rowcount == 1


def _reserve_stock(db: Session, items: list[dict]) -> None:
    """Descuenta existencias con UPDATE condicional: nunca deja el stock negativo."""
    for item in items:
        result = db.execute(
            update(Product)
            .where(Product.id == item["product_id"], Product.stock >= item["quantity"])
            .values(stock=Product.stock - item["quantity"])
        )
        if result.rowcount != 1:
            db.rollback()  # deshace también lo ya descontado en esta misma transacción
            raise HTTPException(409, "Sin existencias suficientes")
    db.commit()


def _release_stock(db: Session, items: list[dict]) -> None:
    for item in items:
        db.execute(
            update(Product).where(Product.id == item["product_id"]).values(stock=Product.stock + item["quantity"])
        )
    db.commit()


def _compensate(db: Session, order: Order, items: list[dict], *, stock: bool, coupon: bool, final_status: str) -> None:
    """Deshace lo reservado antes de cobrar y deja la orden en su estado final."""
    order_id = order.order_id
    db.rollback()
    if coupon:
        release_coupon(db, order)
    if stock:
        _release_stock(db, items)
    _set_status(db, order_id, final_status)


def _charge_and_confirm(db: Session, order: Order, body: SignedOrder) -> dict:
    """Manda la orden firmada al Banco, verifica el recibo y marca la orden como pagada."""
    try:
        response = process_payment(body.model_dump())
    except httpx.HTTPError:
        raise HTTPException(502, "No fue posible contactar al banco")

    if response.status_code != 200:
        try:
            detail = response.json().get("detail", "Pago rechazado")
        except ValueError:
            detail = "Pago rechazado"
        code = response.status_code if response.status_code in (400, 402, 409) else 502
        raise HTTPException(code, detail)

    data = response.json()
    receipt, signature = data["receipt"], data["signature"]

    # El recibo debe venir firmado por el Banco y coincidir con la compra.
    if not verify(settings.bank_signing_public_key, receipt, signature):
        raise SuspectReceipt(502, "Recibo del banco con firma inválida")
    if (
        receipt.get("status") != "approved"
        or receipt.get("order_id") != order.order_id
        or receipt.get("amount_cents") != order.total_cents
    ):
        raise SuspectReceipt(502, "Recibo del banco inconsistente")

    order.status = PAID
    order.receipt_json = json.dumps(receipt)
    order.receipt_signature = signature
    db.commit()

    return {"order_id": order.order_id, "status": PAID, "receipt": receipt, "signature": signature}


@router.post("/{order_id}/pay")
def pay_order(order_id: str, body: SignedOrder, user_id: str = Depends(current_user_id), db: Session = Depends(get_db)):
    """Recibe la orden firmada por la Wallet, la manda al Banco y verifica el recibo firmado."""
    order = _get_own_order(db, order_id, user_id)
    if order.status != PENDING:
        raise HTTPException(409, NOT_PAYABLE)

    signed = body.order
    if (
        signed.order_id != order_id
        or signed.amount_cents != order.total_cents
        or signed.merchant != MERCHANT
        or signed.currency != order.currency
    ):
        raise HTTPException(400, "La orden firmada no coincide con la compra")

    # 1) Reclamar la orden: si dos peticiones llegan a la vez, solo una continúa.
    if not _claim_order(db, order_id):
        raise HTTPException(409, NOT_PAYABLE)

    items = json.loads(order.items_json)
    stock_reserved = coupon_reserved = False
    try:
        # 2) Reservar existencias y cupón ANTES de cobrar.
        _reserve_stock(db, items)
        stock_reserved = True
        if order.coupon_code:
            reserve_coupon(db, order, user_id)
            coupon_reserved = True
        # 3) Cobrar y verificar el recibo.
        return _charge_and_confirm(db, order, body)
    except SuspectReceipt:
        # El Banco pudo haber cobrado: no se reintenta sola, queda para revisión.
        _compensate(db, order, items, stock=stock_reserved, coupon=coupon_reserved, final_status=FAILED)
        raise
    except Exception:
        # Nada se cobró: se devuelve todo y la orden se puede volver a intentar.
        _compensate(db, order, items, stock=stock_reserved, coupon=coupon_reserved, final_status=PENDING)
        raise


@router.get("/{order_id}")
def get_order(order_id: str, user_id: str = Depends(current_user_id), db: Session = Depends(get_db)):
    order = _get_own_order(db, order_id, user_id)
    return {
        "order_id": order.order_id,
        "status": order.status,
        "amount_cents": order.total_cents,
        "subtotal_cents": order.subtotal_cents,
        "discount_cents": order.discount_cents,
        "coupon_code": order.coupon_code,
        "currency": order.currency,
        "items": json.loads(order.items_json),
        "receipt": json.loads(order.receipt_json) if order.receipt_json else None,
        "signature": order.receipt_signature,
    }