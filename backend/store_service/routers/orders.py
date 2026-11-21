import json
import secrets
import time

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from shared.config import settings
from shared.schemas import TICKET_DENOMINATIONS, SignedOrder, SignedTicket
from shared.security.hashing import sha256_hex
from shared.security.signing import canonical_json, verify
from store_service.bank_client import process_payment, redeem_tickets
from store_service.database import get_db
from store_service.deps import current_user_id
from store_service.models import Order, Product, SpentTicket
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
    if order.status == "cancelled":
        raise HTTPException(409, "La orden fue cancelada")
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


def _summary(db: Session, order: Order) -> dict:
    """Resumen de una orden para el historial: incluye nombres de producto y lo realmente cobrado."""
    names = {p.id: p.name for p in db.scalars(select(Product))}
    items = [
        {
            "product_id": i["product_id"],
            "name": names.get(i["product_id"], f"Producto {i['product_id']}"),
            "quantity": i["quantity"],
            "unit_price_cents": i["unit_price_cents"],
        }
        for i in json.loads(order.items_json)
    ]
    receipt = json.loads(order.receipt_json) if order.receipt_json else None
    return {
        "order_id": order.order_id,
        "status": order.status,
        "amount_cents": order.total_cents,
        "subtotal_cents": order.subtotal_cents,
        "discount_cents": order.discount_cents,
        "coupon_code": order.coupon_code,
        "currency": order.currency,
        "created_at": order.created_at.isoformat(),
        "items": items,
        "items_count": sum(i["quantity"] for i in items),
        "charged_cents": receipt.get("charged_cents", order.total_cents) if receipt else None,
        "bank_discount_cents": receipt.get("discount_cents", 0) if receipt else 0,
        "receipt": receipt,
        "signature": order.receipt_signature,
    }


# Debe ir antes de "/{order_id}" para que no se confunda con un id.
@router.get("")
def list_orders(
    limit: int = Query(20, ge=1, le=100),
    status: str | None = Query(default=None, pattern="^(pending|paid|cancelled)$"),
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
):
    """Historial del usuario autenticado (más recientes primero). Nunca muestra órdenes ajenas."""
    stmt = select(Order).where(Order.user_id == user_id)
    if status:
        stmt = stmt.where(Order.status == status)
    stmt = stmt.order_by(Order.created_at.desc(), Order.order_id.desc()).limit(limit)
    return [_summary(db, o) for o in db.scalars(stmt)]


@router.post("/{order_id}/cancel")
def cancel_order(order_id: str, user_id: str = Depends(current_user_id), db: Session = Depends(get_db)):
    """Cancela una orden pendiente. Una orden pagada no se puede cancelar desde aquí."""
    order = _get_own_order(db, order_id, user_id)
    if order.status != "pending":
        raise HTTPException(409, "Solo se pueden cancelar órdenes pendientes")
    order.status = "cancelled"
    db.commit()
    return {"order_id": order.order_id, "status": order.status}


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

class PayWithTicketsIn(BaseModel):
    tickets: list[SignedTicket] = Field(min_length=1, max_length=20)


def _verify_tickets_locally(db: Session, order: Order, user_id: str, tickets: list[SignedTicket]) -> None:
    """Punto 6: la Tienda verifica criptográficamente cada ticket ANTES de contactar al Banco."""
    now_ts = int(time.time())
    seen: set[str] = set()
    total_value = 0

    for item in tickets:
        t = item.ticket
        if t.ticket_id in seen:
            raise HTTPException(400, "No puedes enviar el mismo ticket dos veces")
        seen.add(t.ticket_id)

        # 1) Verificar firma digital Ed25519 con la clave pública del Banco
        if not verify(settings.bank_signing_public_key, t.model_dump(), item.signature):
            raise HTTPException(400, "Ticket con firma digital inválida")

        # 2) Denominación, moneda, vigencia y pertenencia
        if t.amount_cents not in TICKET_DENOMINATIONS:
            raise HTTPException(400, "Denominación de ticket no válida")
        if t.currency != order.currency:
            raise HTTPException(400, "Moneda del ticket no coincide con la orden")
        if t.owner_ref != user_id:
            raise HTTPException(403, "El ticket no pertenece a tu cuenta")
        if t.expires_at <= now_ts:
            raise HTTPException(400, "Uno de los tickets está expirado")

        # 3) Control local de doble gasto en la Tienda
        if db.get(SpentTicket, t.ticket_id) is not None:
            raise HTTPException(409, "Ticket ya utilizado anteriormente")

        total_value += t.amount_cents

    if total_value < order.total_cents:
        raise HTTPException(400, "El valor total de los tickets no cubre el monto de la orden")


def _redeem_tickets_and_confirm(db: Session, order: Order, user_id: str, tickets: list[SignedTicket]) -> dict:
    payload = {
        "order_id": order.order_id,
        "merchant": MERCHANT,
        "amount_cents": order.total_cents,
        "currency": order.currency,
        "payer": user_id,
        "tickets": [t.model_dump() for t in tickets],
    }
    try:
        response = redeem_tickets(payload)
    except httpx.HTTPError:
        raise HTTPException(502, "No fue posible contactar al banco")

    if response.status_code != 200:
        try:
            detail = response.json().get("detail", "Tickets rechazados por el banco")
        except ValueError:
            detail = "Tickets rechazados por el banco"
        code = response.status_code if response.status_code in (400, 402, 403, 409) else 502
        raise HTTPException(code, detail)

    data = response.json()
    receipt, signature = data["receipt"], data["signature"]

    if not verify(settings.bank_signing_public_key, receipt, signature):
        raise HTTPException(502, "Recibo del banco con firma inválida")
    if (
        receipt.get("status") != "approved"
        or receipt.get("order_id") != order.order_id
        or receipt.get("amount_cents") != order.total_cents
    ):
        raise HTTPException(502, "Recibo del banco inconsistente")

    for item in tickets:
        db.add(
            SpentTicket(
                ticket_id=item.ticket.ticket_id,
                order_id=order.order_id,
                amount_cents=item.ticket.amount_cents,
                ticket_hash=sha256_hex(canonical_json(item.ticket.model_dump())),
            )
        )

    for item in json.loads(order.items_json):
        product = db.get(Product, item["product_id"])
        product.stock -= item["quantity"]

    order.status = "paid"
    order.receipt_json = json.dumps(receipt)
    order.receipt_signature = signature
    db.commit()
    return {"order_id": order.order_id, "status": "paid", "receipt": receipt, "signature": signature}


@router.post("/{order_id}/pay-with-tickets")
def pay_order_with_tickets(
    order_id: str,
    body: PayWithTicketsIn,
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
):
    """Verifica la validez de los tickets electrónicos del Banco y completa la compra."""
    order = _get_own_order(db, order_id, user_id)
    if order.status == "cancelled":
        raise HTTPException(409, "La orden fue cancelada")
    if order.status != "pending":
        raise HTTPException(409, "La orden ya fue pagada")

    _verify_tickets_locally(db, order, user_id, body.tickets)

    has_coupon = bool(order.coupon_code)
    if has_coupon:
        reserve_coupon(db, order, user_id)
    try:
        return _redeem_tickets_and_confirm(db, order, user_id, body.tickets)
    except Exception:
        if has_coupon:
            release_coupon(db, order)
        raise