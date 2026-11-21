"""Administración del catálogo de la Tienda.

Se protege con la cabecera `X-Admin-Key` (valor de `STORE_ADMIN_KEY` en el .env). Si la
variable está vacía, la administración queda deshabilitada y toda petición responde 401.
"""
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from shared.config import settings
from shared.security.hashing import constant_time_equals
from store_service.database import get_db
from store_service.models import Product
from store_service.routers.products import ProductOut

router = APIRouter(prefix="/admin", tags=["admin"])


def require_admin_key(x_admin_key: str | None = Header(default=None)) -> None:
    expected = settings.store_admin_key
    if not expected or not x_admin_key or not constant_time_equals(x_admin_key, expected):
        raise HTTPException(401, "Clave de administrador inválida")


class ProductCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    description: str = Field(min_length=1, max_length=300)
    price_cents: int = Field(gt=0, le=100_000_000)
    stock: int = Field(ge=0, le=100_000)
    category: str = Field(default="General", min_length=1, max_length=40)


class ProductPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    description: str | None = Field(default=None, min_length=1, max_length=300)
    price_cents: int | None = Field(default=None, gt=0, le=100_000_000)
    stock: int | None = Field(default=None, ge=0, le=100_000)
    category: str | None = Field(default=None, min_length=1, max_length=40)


@router.post("/products", response_model=ProductOut, status_code=201, dependencies=[Depends(require_admin_key)])
def create_product(body: ProductCreate, db: Session = Depends(get_db)):
    product = Product(**body.model_dump())
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


@router.patch("/products/{product_id}", response_model=ProductOut, dependencies=[Depends(require_admin_key)])
def patch_product(product_id: int, body: ProductPatch, db: Session = Depends(get_db)):
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(404, "Producto no encontrado")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(product, field, value)
    db.commit()
    db.refresh(product)
    return product
