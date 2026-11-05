import re

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class RegisterIn(BaseModel):
    email: EmailStr
    full_name: str = Field(min_length=2, max_length=100)
    password: str = Field(min_length=10, max_length=128)

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        if not re.search(r"[A-Za-z]", v) or not re.search(r"\d", v):
            raise ValueError("La contraseña debe incluir letras y números")
        return v


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    email: EmailStr
    full_name: str


class CardIn(BaseModel):
    number: str = Field(min_length=13, max_length=23)
    holder_name: str = Field(min_length=2, max_length=100)
    exp_month: int = Field(ge=1, le=12)
    exp_year: int = Field(ge=2000, le=2100)
    # Nota: NO se acepta ni se almacena el CVV.


class CardOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    token: str
    brand: str
    last4: str
    holder_name: str
    exp_month: int
    exp_year: int


class PaymentRequest(BaseModel):
    order_id: str = Field(min_length=1, max_length=64)
    merchant: str = Field(min_length=1, max_length=100)
    amount_cents: int = Field(gt=0, le=100_000_000)
    currency: str = Field(default="MXN", pattern=r"^[A-Z]{3}$")
    card_id: str | None = None
