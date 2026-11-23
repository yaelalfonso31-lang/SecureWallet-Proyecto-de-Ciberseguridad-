"""Saldo de la Wallet y su conexión con el Banco.

- `POST /wallet/topup`: abona una recarga. Recibe el comprobante que firmó el Banco
  (`/transfers/to-wallet`), verifica su firma Ed25519 y lo abona UNA sola vez.
- `POST /wallet/withdraw`: descuenta el saldo y firma un comprobante `from_wallet`
  que la app entrega al Banco (`/transfers/from-wallet`) para que abone la cuenta.
"""
import secrets
import time
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, EmailStr
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from shared.config import settings
from shared.schemas import SignedVoucher
from shared.security.signing import sign, verify
from shared.timeutil import utcnow
from wallet_service.audit import log_event
from wallet_service.database import get_db
from wallet_service.deps import get_current_user
from wallet_service.models import User, WalletAccount, WalletMovement

router = APIRouter(prefix="/wallet", tags=["wallet"])


class BalanceOut(BaseModel):
    balance_cents: int
    currency: str = "MXN"


class MovementOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    kind: str
    amount_cents: int
    balance_after_cents: int
    concept: str
    reference: str | None = None
    created_at: datetime


class WithdrawIn(BaseModel):
    amount_cents: int = Field(gt=0, le=100_000_000)


class TopupOut(BaseModel):
    status: str  # credited | already_credited
    balance_cents: int

class TransferIn(BaseModel):
    recipient_email: EmailStr
    amount_cents: int = Field(gt=0, le=100_000_000)
    note: str = Field(default="", max_length=140)


class TransferOut(BaseModel):
    transfer_id: str
    recipient_email: str
    recipient_name: str
    amount_cents: int
    balance_cents: int
    note: str
    created_at: datetime


@router.post("/transfer", response_model=TransferOut)
def transfer_p2p(body: TransferIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Envía saldo real de la Wallet a otro usuario registrado por correo."""
    target_email = body.recipient_email.lower().strip()
    if target_email == user.email.lower():
        raise HTTPException(400, "No puedes transferirte saldo a ti mismo")

    recipient = db.scalar(select(User).where(User.email == target_email))
    if recipient is None:
        raise HTTPException(404, "El destinatario no tiene cuenta en SecureWallet")

    sender_account = _get_account(db, user.id)
    if sender_account.balance_cents < body.amount_cents:
        raise HTTPException(402, "Saldo insuficiente en la Wallet")

    recipient_account = _get_account(db, recipient.id)
    transfer_id = uuid.uuid4().hex
    clean_note = body.note.strip()
    suffix = f" ({clean_note})" if clean_note else ""

    _apply(
        db,
        sender_account,
        "debit",
        body.amount_cents,
        f"Envío a {recipient.full_name}{suffix}",
        f"p2p_{transfer_id}_out",
    )
    _apply(
        db,
        recipient_account,
        "credit",
        body.amount_cents,
        f"Recibido de {user.full_name}{suffix}",
        f"p2p_{transfer_id}_in",
    )
    db.commit()

    log_event(db, "wallet_transfer", user.id, detail=f"transfer={transfer_id} to={recipient.id}")
    return TransferOut(
        transfer_id=transfer_id,
        recipient_email=recipient.email,
        recipient_name=recipient.full_name,
        amount_cents=body.amount_cents,
        balance_cents=sender_account.balance_cents,
        note=clean_note,
        created_at=utcnow(),
    )


def _get_account(db: Session, user_id: str) -> WalletAccount:
    """Cuenta de la Wallet del usuario; se crea en 0 la primera vez. Bloquea la fila (PostgreSQL)."""
    account = db.scalar(select(WalletAccount).where(WalletAccount.user_id == user_id).with_for_update())
    if account is None:
        account = WalletAccount(user_id=user_id, balance_cents=0)
        db.add(account)
        db.flush()
    return account


def _apply(db: Session, account: WalletAccount, kind: str, amount: int, concept: str, reference: str | None) -> None:
    account.balance_cents += amount if kind == "credit" else -amount
    account.updated_at = utcnow()
    db.add(
        WalletMovement(
            user_id=account.user_id,
            kind=kind,
            amount_cents=amount,
            balance_after_cents=account.balance_cents,
            concept=concept,
            reference=reference,
        )
    )


@router.get("/balance", response_model=BalanceOut)
def get_balance(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    account = db.get(WalletAccount, user.id)
    return BalanceOut(balance_cents=account.balance_cents if account else 0)


@router.get("/movements", response_model=list[MovementOut])
def get_movements(
    limit: int = Query(20, ge=1, le=100),
    before: int | None = Query(default=None),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    stmt = select(WalletMovement).where(WalletMovement.user_id == user.id)
    if before is not None:
        stmt = stmt.where(WalletMovement.id < before)
    return list(db.scalars(stmt.order_by(WalletMovement.id.desc()).limit(limit)))


@router.post("/topup", response_model=TopupOut)
def topup(body: SignedVoucher, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Abona una recarga firmada por el Banco. Reenviar el mismo comprobante no abona dos veces."""
    voucher = body.voucher.model_dump()

    # 1) Autenticidad e integridad: el comprobante lo firmó el Banco y no cambió.
    if not verify(settings.bank_signing_public_key, voucher, body.signature):
        raise HTTPException(400, "Firma del Banco inválida")
    # 2) Dirección y dueño (anti-IDOR): debe ser una recarga para ESTE usuario.
    if voucher["direction"] != "to_wallet":
        raise HTTPException(400, "Dirección inválida")
    if voucher["owner_ref"] != user.id:
        raise HTTPException(403, "El comprobante no pertenece a tu Wallet")
    # 3) Vigencia.
    if abs(time.time() - voucher["timestamp"]) > settings.wallet_voucher_max_age_seconds:
        raise HTTPException(400, "Comprobante expirado")

    # 4) Idempotencia: si ya se abonó, devolvemos el saldo actual sin abonar de nuevo.
    transfer_id = voucher["transfer_id"]
    account = _get_account(db, user.id)
    already = db.scalar(select(WalletMovement.id).where(WalletMovement.reference == transfer_id))
    if already is not None:
        return TopupOut(status="already_credited", balance_cents=account.balance_cents)

    _apply(db, account, "credit", voucher["amount_cents"], "Recarga desde el Banco", transfer_id)
    try:
        db.commit()
    except IntegrityError:
        # Dos peticiones simultáneas con el mismo comprobante: gana una, la otra no abona.
        db.rollback()
        current = db.get(WalletAccount, user.id)
        return TopupOut(status="already_credited", balance_cents=current.balance_cents if current else 0)

    log_event(db, "wallet_topup", user.id, detail=f"transfer={transfer_id}")
    return TopupOut(status="credited", balance_cents=account.balance_cents)


@router.post("/withdraw", response_model=SignedVoucher)
def withdraw(body: WithdrawIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Descuenta el saldo y firma el comprobante de retiro que se entrega al Banco."""
    account = _get_account(db, user.id)
    if account.balance_cents < body.amount_cents:
        raise HTTPException(402, "Saldo insuficiente en la Wallet")

    voucher = {
        "transfer_id": uuid.uuid4().hex,
        "owner_ref": user.id,
        "amount_cents": body.amount_cents,
        "nonce": secrets.token_hex(16),
        "timestamp": int(time.time()),
        "direction": "from_wallet",
    }
    signature = sign(settings.wallet_signing_private_key, voucher)
    _apply(db, account, "debit", body.amount_cents, "Retiro hacia el Banco", voucher["transfer_id"])
    db.commit()
    log_event(db, "wallet_withdraw", user.id, detail=f"transfer={voucher['transfer_id']}")
    return SignedVoucher(voucher=voucher, signature=signature)
