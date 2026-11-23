from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import inspect, text

from shared.http import harden_app
from wallet_service.database import Base, engine
from wallet_service.routers import auth, bank_link, cards, payments, security, wallet


def _ensure_wallet_schema() -> None:
    inspector = inspect(engine)
    if "users" not in inspector.get_table_names():
        return
    cols = {c["name"] for c in inspector.get_columns("users")}
    with engine.begin() as conn:
        if "totp_secret" not in cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN totp_secret VARCHAR(64)"))
        if "totp_enabled" not in cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN totp_enabled BOOLEAN NOT NULL DEFAULT 0"))


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    _ensure_wallet_schema()
    yield


app = FastAPI(title="SecureWallet - Wallet Service", version="0.1.0", lifespan=lifespan)
harden_app(app)

app.include_router(auth.router)
app.include_router(bank_link.router)
app.include_router(cards.router)
app.include_router(payments.router)
app.include_router(security.router)
app.include_router(wallet.router)


@app.get("/health", tags=["health"])
def health():
    return {"service": "wallet", "status": "ok"}