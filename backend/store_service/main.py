from contextlib import asynccontextmanager
from datetime import timedelta

from fastapi import FastAPI
from sqlalchemy import select

from shared.http import harden_app
from shared.timeutil import utcnow
from store_service.database import Base, SessionLocal, engine
from store_service.migrations import ensure_schema
from store_service.models import Coupon, Product
from store_service.routers import admin, cart, orders, products

SEED_PRODUCTS = [
    ("Audífonos Bluetooth", "Audífonos inalámbricos con cancelación de ruido", 79900, 25, "Audio"),
    ("Teclado mecánico", "Teclado mecánico compacto, switches rojos", 129900, 15, "Computación"),
    ("Mochila para laptop", "Mochila impermeable de 15 pulgadas", 59900, 30, "Accesorios"),
    ("Cargador USB-C 65W", "Cargador rápido para laptop y celular", 49900, 40, "Computación"),
    ("Libro: Criptografía aplicada", "Introducción práctica a la criptografía", 39900, 10, "Libros"),
    ("Bocina portátil", "Bocina Bluetooth resistente al agua, 12 h de batería", 89900, 20, "Audio"),
    ("Mouse inalámbrico", "Mouse ergonómico silencioso con receptor USB", 29900, 35, "Computación"),
    ("Cable USB-C trenzado", "Cable de carga y datos de 2 metros", 14900, 60, "Accesorios"),
    ("Libro: Redes y seguridad", "Fundamentos de redes con prácticas de seguridad", 44900, 12, "Libros"),
    ("Soporte para laptop", "Soporte de aluminio plegable y ajustable", 34900, 25, "Accesorios"),
]


def _seed_coupons() -> list[Coupon]:
    return [
        Coupon(code="BIENVENIDA10", kind="percent", value=10),
        Coupon(
            code="AHORRA100",
            kind="fixed",
            value=10000,  # $100.00
            min_purchase_cents=50000,
            max_uses=100,
            expires_at=utcnow() + timedelta(days=365),
        ),
    ]


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    ensure_schema(engine)
    with SessionLocal() as db:
        if db.scalar(select(Product)) is None:
            db.add_all(
                Product(name=n, description=d, price_cents=p, stock=s, category=c)
                for n, d, p, s, c in SEED_PRODUCTS
            )
            db.commit()
        if db.scalar(select(Coupon)) is None:
            db.add_all(_seed_coupons())
            db.commit()
    yield


app = FastAPI(title="SecureWallet - Store Service (simulada)", version="0.1.0", lifespan=lifespan)
harden_app(app)

app.include_router(admin.router)
app.include_router(products.router)
app.include_router(cart.router)
app.include_router(orders.router)


@app.get("/health", tags=["health"])
def health():
    return {"service": "store", "status": "ok"}
