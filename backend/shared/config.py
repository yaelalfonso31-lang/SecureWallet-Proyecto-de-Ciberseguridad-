from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuración común. Los valores vienen de variables de entorno o de .env."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    environment: str = "dev"

    wallet_database_url: str = "sqlite:///./wallet.db"
    bank_database_url: str = "sqlite:///./bank.db"
    store_database_url: str = "sqlite:///./store.db"

    jwt_secret: str = ""
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15

    data_encryption_key: str = ""  # base64url de 32 bytes (AES-256)

    wallet_signing_private_key: str = ""
    wallet_signing_public_key: str = ""
    bank_signing_private_key: str = ""
    bank_signing_public_key: str = ""

    bank_api_key: str = ""
    bank_url: str = "http://localhost:8002"

    max_failed_logins: int = 5
    lockout_minutes: int = 15
    order_max_age_seconds: int = 120


settings = Settings()
