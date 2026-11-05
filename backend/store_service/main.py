from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import select

from shared.http import harden_app
from store_service.database import Base, SessionLocal, engine
from store_service.models import Product
from store_service.routers import orders, products

SEED_PRODUCTS = [
    ("Audífonos Bluetooth", "Audífonos inalámbricos con cancelación de ruido", 79900, 25),
    ("Teclado mecánico", "Teclado mecánico compacto, switches rojos", 129900, 15),
    ("Mochila para laptop", "Mochila impermeable de 15 pulgadas", 59900, 30),
    ("Cargador USB-C 65W", "Cargador rápido para laptop y celular", 49900, 40),
    ("Libro: Criptografía aplicada", "Introducción práctica a la criptografía", 39900, 10),
]


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        if db.scalar(select(Product)) is None:
            db.add_all(
                Product(name=n, description=d, price_cents=p, stock=s) for n, d, p, s in SEED_PRODUCTS
            )
            db.commit()
    yield


app = FastAPI(title="SecureWallet - Store Service (simulada)", version="0.1.0", lifespan=lifespan)
harden_app(app)

app.include_router(products.router)
app.include_router(orders.router)


@app.get("/health", tags=["health"])
def health():
    return {"service": "store", "status": "ok"}
