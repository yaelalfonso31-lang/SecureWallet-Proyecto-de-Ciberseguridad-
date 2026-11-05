from datetime import datetime, timezone


def utcnow() -> datetime:
    """Fecha/hora UTC sin zona horaria (naive), consistente con SQLite y PostgreSQL."""
    return datetime.now(timezone.utc).replace(tzinfo=None)
