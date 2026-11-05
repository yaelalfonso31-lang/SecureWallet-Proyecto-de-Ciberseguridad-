from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import select

from bank_service.database import Base, SessionLocal, engine
from bank_service.models import Promotion
from bank_service.routers import promotions, transactions
from shared.http import harden_app

SEED_PROMOTIONS = [
    ("Bono de bienvenida", "10% de descuento en tu primera compra con la Wallet", 10),
    ("Fin de semana tecnológico", "15% en electrónica pagando con la Wallet", 15),
    ("Cashback libros", "5% de devolución en libros y papelería", 5),
]


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        if db.scalar(select(Promotion)) is None:
            db.add_all(
                Promotion(title=t, description=d, discount_percent=p) for t, d, p in SEED_PROMOTIONS
            )
            db.commit()
    yield


app = FastAPI(title="SecureWallet - Bank Service (simulado)", version="0.1.0", lifespan=lifespan)
harden_app(app)

app.include_router(promotions.router)
app.include_router(transactions.router)


@app.get("/health", tags=["health"])
def health():
    return {"service": "bank", "status": "ok"}
