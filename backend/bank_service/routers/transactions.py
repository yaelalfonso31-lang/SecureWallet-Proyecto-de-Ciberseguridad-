import json
import uuid

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from bank_service.database import get_db
from bank_service.models import Account, Movement, ProcessedOrder, Promotion, PromotionRedemption
from bank_service.verification import ensure_fresh, ensure_nonce_unique, verify_wallet_signature
from shared.config import settings
from shared.schemas import SignedOrder, SignedReceipt
from shared.security.hashing import constant_time_equals, sha256_hex
from shared.security.signing import canonical_json, sign
from shared.timeutil import utcnow

router = APIRouter(tags=["transactions"])


def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
    """Autenticación servicio-a-servicio (Tienda -> Banco).

    TODO equipo Banco: reemplazar por mTLS entre servicios.
    """
    expected = settings.bank_api_key
    if not expected or not x_api_key or not constant_time_equals(x_api_key, expected):
        raise HTTPException(401, "API key inválida")


def _get_account_for_update(db: Session, owner_ref: str) -> Account:
    """Búsqueda estricta: la cuenta ya debe estar dada de alta.

    Nunca crea cuentas (antes se regalaban $1,000 a cualquier payer desconocido).
    `with_for_update` bloquea la fila en PostgreSQL para evitar dos cobros
    simultáneos; en SQLite se ignora sin efecto.
    """
    account = db.scalar(select(Account).where(Account.owner_ref == owner_ref).with_for_update())
    if account is None:
        raise HTTPException(404, "Cuenta no encontrada")
    if account.status == "frozen":
        raise HTTPException(403, "Cuenta congelada")
    return account


@router.get("/bank/public-key")
def bank_public_key():
    """Clave pública con la que se verifican los recibos firmados por el Banco."""
    return {"algorithm": "Ed25519", "public_key": settings.bank_signing_public_key}


@router.post("/transactions/process", response_model=SignedReceipt, dependencies=[Depends(require_api_key)])
def process_transaction(body: SignedOrder, db: Session = Depends(get_db)):
    order = body.order.model_dump()

    # 1) Autenticidad e integridad: la firma debe ser de la Wallet y la orden no pudo cambiar.
    verify_wallet_signature(order, body.signature)

    # 2) Frescura: rechaza órdenes viejas (ventana corta anti-replay).
    ensure_fresh(order["timestamp"])

    # 3) Unicidad: el mismo nonce/order_id no se procesa dos veces.
    ensure_nonce_unique(db, ProcessedOrder, order["nonce"])
    if db.scalar(select(ProcessedOrder).where(ProcessedOrder.order_id == order["order_id"])):
        raise HTTPException(409, "Orden ya procesada")

    # 4) Fondos: la cuenta debe existir y estar activa.
    account = _get_account_for_update(db, order["payer"])

    # 5) Canje pendiente (si lo hay): el Banco, nunca la app ni la Tienda, calcula
    #    el descuento. Se toma el canje más antiguo sin usar y se bloquea la fila.
    redemption = db.scalar(
        select(PromotionRedemption)
        .where(
            PromotionRedemption.account_id == account.id,
            PromotionRedemption.used_in_order_id.is_(None),
        )
        .order_by(PromotionRedemption.id)
        .limit(1)
        .with_for_update()
    )
    discount_cents = 0
    promotion_id = None
    if redemption is not None:
        promotion = db.get(Promotion, redemption.promotion_id)
        promotion_id = promotion.id
        discount_cents = order["amount_cents"] * promotion.discount_percent // 100

    # 6) Se cobra el monto con descuento. `amount_cents` NO cambia, porque la
    #    Tienda lo compara con el total de su orden.
    charged_cents = order["amount_cents"] - discount_cents
    if account.balance_cents < charged_cents:
        raise HTTPException(402, "Fondos insuficientes")
    account.balance_cents -= charged_cents
    if redemption is not None:
        redemption.used_in_order_id = order["order_id"]  # el canje es de un solo uso

    # 7) Movimiento inmutable por lo realmente cobrado, en el mismo commit.
    db.add(
        Movement(
            account_id=account.id,
            kind="debit",
            amount_cents=charged_cents,
            balance_after_cents=account.balance_cents,
            concept=f"Pago de orden {order['order_id']}",
            reference=order["order_id"],
        )
    )

    # 8) Recibo firmado por el Banco (no repudio), con el desglose del descuento.
    receipt = {
        "receipt_id": uuid.uuid4().hex,
        "order_id": order["order_id"],
        "payer": order["payer"],
        "amount_cents": order["amount_cents"],
        "discount_cents": discount_cents,
        "charged_cents": charged_cents,
        "promotion_id": promotion_id,
        "currency": order["currency"],
        "status": "approved",
        "processed_at": utcnow().isoformat(),
        "order_hash": sha256_hex(canonical_json(order)),
    }
    signature = sign(settings.bank_signing_private_key, receipt)

    db.add(
        ProcessedOrder(
            order_id=order["order_id"],
            nonce=order["nonce"],
            payer=order["payer"],
            amount_cents=order["amount_cents"],
            receipt_json=json.dumps(receipt),
        )
    )
    db.commit()
    return SignedReceipt(receipt=receipt, signature=signature)
