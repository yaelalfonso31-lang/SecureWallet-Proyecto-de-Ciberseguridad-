import json
import secrets
import time
import uuid
from datetime import datetime, time as dtime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from bank_service.database import get_db
from bank_service.deps import require_scope
from bank_service.models import Account, BankCustomer, Movement, Transfer
from bank_service.verification import ensure_fresh, ensure_nonce_unique, verify_wallet_signature
from shared.config import settings
from shared.schemas import SignedVoucher, TransferVoucher  # noqa: F401 (TransferVoucher documenta el contrato)
from shared.security.signing import sign
from shared.timeutil import utcnow

router = APIRouter(tags=["transfers"])


class ToWalletIn(BaseModel):
    amount_cents: int = Field(gt=0, le=100_000_000)
    idempotency_key: str = Field(min_length=1, max_length=64)


def _get_own_account(db: Session, customer: BankCustomer) -> Account:
    """Cuenta del dueño del token (anti-IDOR), bloqueada para evitar cargos concurrentes."""
    account = db.scalar(select(Account).where(Account.customer_id == customer.id).with_for_update())
    if account is None:
        raise HTTPException(404, "Cuenta no encontrada")
    if account.status == "frozen":
        raise HTTPException(403, "Cuenta congelada")
    return account


def _today_spent_to_wallet(db: Session, account_id: int) -> int:
    """Suma de lo recargado hoy (UTC) hacia la Wallet, para el límite diario."""
    start_of_day = datetime.combine(utcnow().date(), dtime.min)
    total = db.scalar(
        select(func.coalesce(func.sum(Transfer.amount_cents), 0)).where(
            Transfer.account_id == account_id,
            Transfer.direction == "to_wallet",
            Transfer.created_at >= start_of_day,
        )
    )
    return total or 0


@router.post("/transfers/to-wallet", response_model=SignedVoucher)
def transfer_to_wallet(
    body: ToWalletIn,
    db: Session = Depends(get_db),
    customer: BankCustomer = Depends(require_scope("transfers:write")),
):
    """Recarga: el Banco descuenta de la cuenta y firma un comprobante para la Wallet."""
    # Idempotencia: si la llave ya existe, devolvemos el MISMO comprobante sin cobrar de nuevo.
    existing = db.scalar(select(Transfer).where(Transfer.idempotency_key == body.idempotency_key))
    if existing is not None:
        return SignedVoucher(voucher=json.loads(existing.voucher_json), signature=existing.signature)

    account = _get_own_account(db, customer)

    # Límite diario configurable.
    spent = _today_spent_to_wallet(db, account.id)
    if spent + body.amount_cents > settings.bank_transfer_daily_limit_cents:
        raise HTTPException(429, "Límite diario de recargas excedido")

    # Fondos.
    if account.balance_cents < body.amount_cents:
        raise HTTPException(402, "Fondos insuficientes")

    voucher = {
        "transfer_id": uuid.uuid4().hex,
        "owner_ref": account.owner_ref,
        "amount_cents": body.amount_cents,
        "nonce": secrets.token_hex(16),
        "timestamp": int(time.time()),
        "direction": "to_wallet",
    }
    signature = sign(settings.bank_signing_private_key, voucher)

    account.balance_cents -= body.amount_cents
    db.add(
        Movement(
            account_id=account.id,
            kind="debit",
            amount_cents=body.amount_cents,
            balance_after_cents=account.balance_cents,
            concept="Recarga a la Wallet",
            reference=voucher["transfer_id"],
        )
    )
    db.add(
        Transfer(
            transfer_id=voucher["transfer_id"],
            nonce=voucher["nonce"],
            account_id=account.id,
            direction="to_wallet",
            amount_cents=body.amount_cents,
            idempotency_key=body.idempotency_key,
            voucher_json=json.dumps(voucher),
            signature=signature,
        )
    )
    db.commit()
    return SignedVoucher(voucher=voucher, signature=signature)


@router.post("/transfers/from-wallet")
def transfer_from_wallet(
    body: SignedVoucher,
    db: Session = Depends(get_db),
    customer: BankCustomer = Depends(require_scope("transfers:write")),
):
    """Retiro: la Wallet ya entregó el dinero; el Banco verifica su comprobante y abona."""
    voucher = body.voucher.model_dump()
    account = _get_own_account(db, customer)

    # 1) Autenticidad: el comprobante lo firmó la Wallet.
    verify_wallet_signature(voucher, body.signature)
    # 2) Frescura.
    ensure_fresh(voucher["timestamp"])
    # 3) Dirección y dueño (anti-IDOR): el comprobante debe ser de la cuenta del token.
    if voucher["direction"] != "from_wallet":
        raise HTTPException(400, "Dirección inválida")
    if voucher["owner_ref"] != account.owner_ref:
        raise HTTPException(403, "El comprobante no pertenece a tu cuenta")
    # 4) Anti-replay: el nonce no se había usado.
    ensure_nonce_unique(db, Transfer, voucher["nonce"])

    # 5) Abonar y dejar movimiento, en la misma transacción.
    account.balance_cents += voucher["amount_cents"]
    db.add(
        Movement(
            account_id=account.id,
            kind="credit",
            amount_cents=voucher["amount_cents"],
            balance_after_cents=account.balance_cents,
            concept="Retiro desde la Wallet",
            reference=voucher["transfer_id"],
        )
    )
    db.add(
        Transfer(
            transfer_id=voucher["transfer_id"],
            nonce=voucher["nonce"],
            account_id=account.id,
            direction="from_wallet",
            amount_cents=voucher["amount_cents"],
            idempotency_key=voucher["transfer_id"],
            voucher_json=json.dumps(voucher),
            signature=body.signature,
        )
    )
    db.commit()
    return {"status": "credited", "transfer_id": voucher["transfer_id"], "balance_cents": account.balance_cents}
