import json
import secrets

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from shared.config import settings
from shared.schemas import SignedOrder
from shared.security.signing import verify
from store_service.bank_client import process_payment
from store_service.database import get_db
from store_service.models import Order, Product

router = APIRouter(prefix="/orders", tags=["orders"])

MERCHANT = "SecureStore"


class OrderItemIn(BaseModel):
    product_id: int
    quantity: int = Field(ge=1, le=20)


class OrderCreateIn(BaseModel):
    items: list[OrderItemIn] = Field(min_length=1, max_length=50)


@router.post("", status_code=201)
def create_order(body: OrderCreateIn, db: Session = Depends(get_db)):
    total = 0
    items = []
    for item in body.items:
        product = db.get(Product, item.product_id)
        if product is None:
            raise HTTPException(404, f"Producto {item.product_id} no existe")
        if product.stock < item.quantity:
            raise HTTPException(409, f"Sin existencias de {product.name}")
        total += product.price_cents * item.quantity
        items.append({"product_id": product.id, "quantity": item.quantity, "unit_price_cents": product.price_cents})

    order = Order(order_id="ord_" + secrets.token_hex(8), items_json=json.dumps(items), total_cents=total)
    db.add(order)
    db.commit()
    return {
        "order_id": order.order_id,
        "merchant": MERCHANT,
        "amount_cents": order.total_cents,
        "currency": order.currency,
        "status": order.status,
    }


@router.post("/{order_id}/pay")
def pay_order(order_id: str, body: SignedOrder, db: Session = Depends(get_db)):
    """Recibe la orden firmada por la Wallet, la manda al Banco y verifica el recibo firmado."""
    order = db.get(Order, order_id)
    if order is None:
        raise HTTPException(404, "Orden no encontrada")
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
        or receipt.get("order_id") != order_id
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

    return {"order_id": order_id, "status": "paid", "receipt": receipt, "signature": signature}


@router.get("/{order_id}")
def get_order(order_id: str, db: Session = Depends(get_db)):
    order = db.get(Order, order_id)
    if order is None:
        raise HTTPException(404, "Orden no encontrada")
    return {
        "order_id": order.order_id,
        "status": order.status,
        "amount_cents": order.total_cents,
        "currency": order.currency,
        "items": json.loads(order.items_json),
        "receipt": json.loads(order.receipt_json) if order.receipt_json else None,
        "signature": order.receipt_signature,
    }
