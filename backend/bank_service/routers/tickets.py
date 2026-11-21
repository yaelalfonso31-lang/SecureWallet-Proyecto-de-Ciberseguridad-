"""Emisión y canje de tickets electrónicos prepagados firmados con Ed25519."""
import json
import secrets
import time
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from bank_service.database import get_db
from bank_service.deps import require_scope
from bank_service.models import Account, BankCustomer, BankTicket, Movement, ProcessedOrder
from bank_service.routers.transactions import require_api_key
from shared.config import settings
from shared.schemas import (
    TICKET_DENOMINATIONS,
    ElectronicTicket,
    SignedReceipt,
    SignedTicket,
    TicketRedeemIn,
)
from shared.security.hashing import sha256_hex
from shared.security.signing import canonical_json, sign, verify
from shared.timeutil import utcnow

router = APIRouter(prefix="/tickets", tags=["tickets"])

TICKET_TTL_DAYS = 30
ISSUER_NAME = "BancoAzul"


class PurchaseTicketsIn(BaseModel):
    denomination_cents: int
    quantity: int = Field(default=1, ge=1, le=10)

    @field_validator("denomination_cents")
    @classmethod
    def check_denomination(cls, v: int) -> int:
        if v not in TICKET_DENOMINATIONS:
            raise ValueError("Denominación inválida. Valores permitidos: $50, $100, $200, $500")
        return v


class BankTicketOut(BaseModel):
    ticket: ElectronicTicket
    signature: str
    status: str
    spent_in_order_id: str | None = None


def _get_own_account(db: Session, customer: BankCustomer) -> Account:
    account = db.scalar(select(Account).where(Account.customer_id == customer.id).with_for_update())
    if account is None:
        raise HTTPException(404, "Cuenta no encontrada")
    if account.status == "frozen":
        raise HTTPException(403, "Cuenta congelada")
    return account


@router.get("/denominations")
def list_denominations():
    """Denominaciones fijas disponibles para adquirir tickets electrónicos."""
    return {
        "currency": "MXN",
        "denominations_cents": list(TICKET_DENOMINATIONS),
    }


@router.post("/purchase", response_model=list[BankTicketOut], status_code=201)
def purchase_tickets(
    body: PurchaseTicketsIn,
    db: Session = Depends(get_db),
    customer: BankCustomer = Depends(require_scope("tickets:write")),
):
    """Descuenta el importe de la cuenta bancaria y emite tickets firmados por el Banco."""
    account = _get_own_account(db, customer)
    total_cost = body.denomination_cents * body.quantity
    if account.balance_cents < total_cost:
        raise HTTPException(402, "Fondos insuficientes")

    now_dt = utcnow()
    expires_dt = now_dt + timedelta(days=TICKET_TTL_DAYS)
    now_ts = int(now_dt.replace(tzinfo=timezone.utc).timestamp())
    expires_ts = int(expires_dt.replace(tzinfo=timezone.utc).timestamp())

    created: list[BankTicketOut] = []
    ticket_ids: list[str] = []

    for _ in range(body.quantity):
        ticket_id = "tkt_" + secrets.token_hex(12)
        payload = ElectronicTicket(
            ticket_id=ticket_id,
            issuer=ISSUER_NAME,
            owner_ref=account.owner_ref,
            amount_cents=body.denomination_cents,
            currency="MXN",
            nonce=secrets.token_hex(16),
            issued_at=now_ts,
            expires_at=expires_ts,
        )
        payload_dict = payload.model_dump()
        signature = sign(settings.bank_signing_private_key, payload_dict)
        ticket_hash = sha256_hex(canonical_json(payload_dict))

        db.add(
            BankTicket(
                ticket_id=ticket_id,
                account_id=account.id,
                owner_ref=account.owner_ref,
                amount_cents=body.denomination_cents,
                currency="MXN",
                nonce=payload.nonce,
                ticket_hash=ticket_hash,
                ticket_json=json.dumps(payload_dict),
                signature=signature,
                status="active",
                issued_at=now_dt,
                expires_at=expires_dt,
            )
        )
        ticket_ids.append(ticket_id)
        created.append(BankTicketOut(ticket=payload, signature=signature, status="active"))

    account.balance_cents -= total_cost
    db.add(
        Movement(
            account_id=account.id,
            kind="debit",
            amount_cents=total_cost,
            balance_after_cents=account.balance_cents,
            concept=f"Compra de {body.quantity} ticket(s) de ${body.denomination_cents // 100}",
            reference=ticket_ids[0],
        )
    )
    db.commit()
    return created


@router.get("/me", response_model=list[BankTicketOut])
def my_tickets(
    status: str | None = Query(default=None, pattern="^(active|spent)$"),
    db: Session = Depends(get_db),
    customer: BankCustomer = Depends(require_scope("tickets:read")),
):
    """Lista los tickets electrónicos del cliente autenticado (activos o gastados)."""
    account = db.scalar(select(Account).where(Account.customer_id == customer.id))
    if account is None:
        raise HTTPException(404, "Cuenta no encontrada")

    stmt = select(BankTicket).where(BankTicket.account_id == account.id)
    if status:
        stmt = stmt.where(BankTicket.status == status)
    stmt = stmt.order_by(BankTicket.issued_at.desc())

    rows = list(db.scalars(stmt))
    return [
        BankTicketOut(
            ticket=ElectronicTicket(**json.loads(r.ticket_json)),
            signature=r.signature,
            status=r.status,
            spent_in_order_id=r.spent_in_order_id,
        )
        for r in rows
    ]


@router.post("/redeem", response_model=SignedReceipt, dependencies=[Depends(require_api_key)])
def redeem_tickets(body: TicketRedeemIn, db: Session = Depends(get_db)):
    """Valida y consume tickets electrónicos enviados por la Tienda (anti doble gasto)."""
    if db.scalar(select(ProcessedOrder).where(ProcessedOrder.order_id == body.order_id)):
        raise HTTPException(409, "Orden ya procesada")

    seen_ids: set[str] = set()
    db_tickets: list[BankTicket] = []
    total_tickets_cents = 0
    now_ts = int(time.time())

    for item in body.tickets:
        ticket_dict = item.ticket.model_dump()
        tid = item.ticket.ticket_id

        if tid in seen_ids:
            raise HTTPException(400, "Ticket duplicado en la misma compra")
        seen_ids.add(tid)

        # 1) Firma digital Ed25519 del Banco
        if not verify(settings.bank_signing_public_key, ticket_dict, item.signature):
            raise HTTPException(400, "Ticket con firma digital inválida")

        # 2) Vigencia, moneda y dueño
        if item.ticket.expires_at <= now_ts:
            raise HTTPException(400, "Ticket expirado")
        if item.ticket.currency != body.currency:
            raise HTTPException(400, "Moneda del ticket no coincide")
        if item.ticket.owner_ref != body.payer:
            raise HTTPException(403, "El ticket no pertenece al comprador")

        # 3) Existencia, integridad por hash SHA-256 y control de doble gasto
        row = db.scalar(select(BankTicket).where(BankTicket.ticket_id == tid).with_for_update())
        expected_hash = sha256_hex(canonical_json(ticket_dict))
        if row is None or row.ticket_hash != expected_hash:
            raise HTTPException(400, "Ticket no reconocido o alterado")
        if row.status != "active":
            raise HTTPException(409, "Ticket ya utilizado (doble gasto rechazado)")

        db_tickets.append(row)
        total_tickets_cents += row.amount_cents

    if total_tickets_cents < body.amount_cents:
        raise HTTPException(400, "El monto de los tickets no cubre el total de la compra")

    now_dt = utcnow()
    for row in db_tickets:
        row.status = "spent"
        row.spent_in_order_id = body.order_id
        row.spent_at = now_dt

    # Si los tickets superan el total de la compra, el cambio se reembolsa a la cuenta del cliente.
    change_cents = total_tickets_cents - body.amount_cents
    if change_cents > 0:
        account = db.scalar(select(Account).where(Account.id == db_tickets[0].account_id).with_for_update())
        if account is not None:
            account.balance_cents += change_cents
            db.add(
                Movement(
                    account_id=account.id,
                    kind="credit",
                    amount_cents=change_cents,
                    balance_after_cents=account.balance_cents,
                    concept=f"Cambio de compra con tickets ({body.order_id})",
                    reference=body.order_id,
                )
            )

    ticket_ids = [t.ticket_id for t in db_tickets]
    receipt = {
        "receipt_id": uuid.uuid4().hex,
        "order_id": body.order_id,
        "payer": body.payer,
        "payment_method": "tickets",
        "ticket_ids": ticket_ids,
        "tickets_total_cents": total_tickets_cents,
        "change_cents": change_cents,
        "amount_cents": body.amount_cents,
        "discount_cents": 0,
        "charged_cents": body.amount_cents,
        "promotion_id": None,
        "currency": body.currency,
        "status": "approved",
        "processed_at": now_dt.isoformat(),
        "order_hash": sha256_hex(
            canonical_json({"order_id": body.order_id, "ticket_ids": sorted(ticket_ids), "amount_cents": body.amount_cents})
        ),
    }
    signature = sign(settings.bank_signing_private_key, receipt)

    db.add(
        ProcessedOrder(
            order_id=body.order_id,
            nonce=secrets.token_hex(16),
            payer=body.payer,
            amount_cents=body.amount_cents,
            receipt_json=json.dumps(receipt),
        )
    )
    db.commit()
    return SignedReceipt(receipt=receipt, signature=signature)