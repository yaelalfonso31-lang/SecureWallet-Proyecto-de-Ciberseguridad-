from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from store_service.database import get_db
from store_service.deps import current_user_id
from store_service.pricing import compute_quote
from store_service.schemas import CartQuoteIn

router = APIRouter(prefix="/cart", tags=["cart"])


@router.post("/quote")
def quote_cart(body: CartQuoteIn, user_id: str = Depends(current_user_id), db: Session = Depends(get_db)):
    """Cotiza el carrito. No crea nada: la app solo muestra lo que devuelve el servidor."""
    return compute_quote(db, body.items, body.coupon_code, user_id)