from contextlib import asynccontextmanager

from fastapi import FastAPI

from shared.http import harden_app
from wallet_service.database import Base, engine
from wallet_service.routers import auth, cards, payments


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)  # TODO: migrar a Alembic cuando el esquema se estabilice
    yield


app = FastAPI(title="SecureWallet - Wallet Service", version="0.1.0", lifespan=lifespan)
harden_app(app)

app.include_router(auth.router)
app.include_router(cards.router)
app.include_router(payments.router)


@app.get("/health", tags=["health"])
def health():
    return {"service": "wallet", "status": "ok"}
