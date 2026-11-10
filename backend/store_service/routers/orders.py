import json
import secrets

import httpx
from fastapi import APIRouter, Depends, HTTPException
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
        raise HTTPException(502, "Recibo del banco con firma inválida")
    if (
        receipt.get("status") != "approved"
        or receipt.get("order_id") != order.order_id
        or receipt.get("amount_cents") != order.total_cents
    ):
        raise HTTPException(502, "Recibo del banco inconsistente")

    for item in json.loads(order.items_json):
        product = db.get(Product, item["product_id"])
        product.stock -= item["quantity"]
    order.status = "paid"
    order.receipt_json = json.dumps(receipt)
    order.receipt_signature = signature
    db.commit()

    return {"order_id": order.order_id, "status": "paid", "receipt": receipt, "signature": signature}


@router.post("/{order_id}/pay")
def pay_order(order_id: str, body: SignedOrder, user_id: str = Depends(current_user_id), db: Session = Depends(get_db)):
    """Recibe la orden firmada por la Wallet, la manda al Banco y verifica el recibo firmado."""
    order = _get_own_order(db, order_id, user_id)
    if order.status != "pending":
        raise HTTPException(409, "La orden ya fue pagada")

    signed = body.order
    if (
        signed.order_id != order_id
        or signed.amount_cents != order.total_cents
        or signed.merchant != MERCHANT
        or signed.currency != order.currency
    ):
        raise HTTPException(400, "La orden firmada no coincide con la compra")

    # Se consume el cupón antes de cobrar; si el pago falla, se devuelve.
    has_coupon = bool(order.coupon_code)
    if has_coupon:
        reserve_coupon(db, order, user_id)
    try:
        return _charge_and_confirm(db, order, body)
    except Exception:
        if has_coupon:
            release_coupon(db, order)
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