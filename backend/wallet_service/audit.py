from sqlalchemy import select
from sqlalchemy.orm import Session

from shared.security.hashing import chain_hash
from shared.timeutil import utcnow
from wallet_service.models import AuditLog

GENESIS = "0" * 64


def _record(event: str, user_id, detail: str, created_at) -> dict:
    return {
        "event": event,
        "user_id": user_id,
        "detail": detail,
        "created_at": created_at.isoformat(),
    }


def log_event(db: Session, event: str, user_id: str | None = None, detail: str = "") -> None:
    """Registra un evento. Nunca guardes contraseñas, PAN ni tokens en `detail`."""
    last = db.scalars(select(AuditLog).order_by(AuditLog.id.desc())).first()
    prev_hash = last.hash if last else GENESIS
    created_at = utcnow()
    entry = AuditLog(
        event=event,
        user_id=user_id,
        detail=detail,
        prev_hash=prev_hash,
        hash=chain_hash(prev_hash, _record(event, user_id, detail, created_at)),
        created_at=created_at,
    )
    db.add(entry)
    db.commit()


def verify_chain(db: Session) -> bool:
    """True si ningún registro de la bitácora fue alterado."""
    prev_hash = GENESIS
    for row in db.scalars(select(AuditLog).order_by(AuditLog.id)):
        expected = chain_hash(prev_hash, _record(row.event, row.user_id, row.detail, row.created_at))
        if row.prev_hash != prev_hash or row.hash != expected:
            return False
        prev_hash = row.hash
    return True
