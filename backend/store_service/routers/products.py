from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.orm import Session

from store_service.database import get_db
from store_service.models import Product

router = APIRouter(prefix="/products", tags=["products"])


class ProductOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    description: str
    price_cents: int
    stock: int
    category: str



@router.get("", response_model=list[ProductOut])
def list_products(
    q: str | None = Query(default=None, max_length=60, description="Busca en nombre y descripción"),
    category: str | None = Query(default=None, max_length=40),
    db: Session = Depends(get_db),
):
    """Catálogo. `q` y `category` son opcionales; sin ellos devuelve todo."""
    stmt = select(Product).order_by(Product.id)
    if category:
        stmt = stmt.where(Product.category == category)
    if q and q.strip():
        pattern = f"%{q.strip()}%"
        stmt = stmt.where(Product.name.ilike(pattern) | Product.description.ilike(pattern))
    return list(db.scalars(stmt))


# Esta ruta va ANTES de "/{product_id}" para que "categories" no se interprete como un id.
@router.get("/categories", response_model=list[str])
def list_categories(db: Session = Depends(get_db)):
    return list(db.scalars(select(Product.category).distinct().order_by(Product.category)))


@router.get("/{product_id}", response_model=ProductOut)
def get_product(product_id: int, db: Session = Depends(get_db)):
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(404, "Producto no encontrado")
    return product
