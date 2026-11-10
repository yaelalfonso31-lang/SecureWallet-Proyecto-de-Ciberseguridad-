from pydantic import BaseModel, Field


class OrderItemIn(BaseModel):
    product_id: int
    quantity: int = Field(ge=1, le=20)


class CartQuoteIn(BaseModel):
    items: list[OrderItemIn] = Field(min_length=1, max_length=50)
    coupon_code: str | None = Field(default=None, min_length=1, max_length=32)


class OrderCreateIn(CartQuoteIn):
    pass