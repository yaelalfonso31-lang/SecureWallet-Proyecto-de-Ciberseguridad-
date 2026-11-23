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

    # JWT propio del Banco (aud="bank"). Debe ser DISTINTO de jwt_secret.
    bank_jwt_secret: str = ""

    data_encryption_key: str = ""  # base64url de 32 bytes (AES-256)

    wallet_signing_private_key: str = ""
    wallet_signing_public_key: str = ""
    bank_signing_private_key: str = ""
    bank_signing_public_key: str = ""

    bank_api_key: str = ""
    bank_url: str = "http://localhost:8002"

    # mTLS Tienda -> Banco (B7)
    mtls_ca_cert: str = "certs/ca.pem"
    mtls_store_cert: str = "certs/store.pem"
    mtls_store_key: str = "certs/store.key"
    mtls_bank_cert: str = "certs/bank.pem"
    mtls_bank_key: str = "certs/bank.key"

    max_failed_logins: int = 5
    lockout_minutes: int = 15
    order_max_age_seconds: int = 120
    rate_limit_per_minute: int = 120
    cors_origins: str = "http://localhost,http://127.0.0.1"

    # Límite diario de transferencias banco -> wallet por cuenta (B5), en centavos.
    bank_transfer_daily_limit_cents: int = 1_000_000

     # Saldo de demostración con el que se abre una cuenta nueva del Banco simulado.
    bank_open_account_balance_cents: int = 500_000

    # Vigencia con la que la Wallet acepta un comprobante de recarga firmado por el Banco.
    # Es más larga que `order_max_age_seconds` porque la recarga ya descontó el dinero y no
    # debe perderse si la app tarda en entregar el comprobante. La unicidad la da `transfer_id`.
    wallet_voucher_max_age_seconds: int = 3600

    # Clave del administrador de la Tienda (cabecera X-Admin-Key). Vacía = administración deshabilitada.
    store_admin_key: str = ""


settings = Settings()
