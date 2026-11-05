"""Cifrado autenticado AES-256-GCM para datos en reposo (p. ej. número de tarjeta)."""
import base64
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from shared.config import settings


def generate_key() -> str:
    return base64.urlsafe_b64encode(AESGCM.generate_key(bit_length=256)).decode()


def _load_key() -> bytes:
    if not settings.data_encryption_key:
        raise RuntimeError("DATA_ENCRYPTION_KEY no está configurada (ver scripts/generate_env.py)")
    key = base64.urlsafe_b64decode(settings.data_encryption_key)
    if len(key) != 32:
        raise RuntimeError("DATA_ENCRYPTION_KEY debe ser de 32 bytes")
    return key


def encrypt(plaintext: str, aad: str = "") -> str:
    """Cifra y devuelve base64url(nonce || ciphertext+tag).

    `aad` (datos asociados, p. ej. el id del usuario) liga el cifrado a su dueño:
    si alguien copia el valor a otro registro, el descifrado falla.
    """
    nonce = os.urandom(12)  # nonce único por cifrado, nunca reutilizar
    ciphertext = AESGCM(_load_key()).encrypt(nonce, plaintext.encode(), aad.encode() or None)
    return base64.urlsafe_b64encode(nonce + ciphertext).decode()


def decrypt(token: str, aad: str = "") -> str:
    raw = base64.urlsafe_b64decode(token)
    nonce, ciphertext = raw[:12], raw[12:]
    return AESGCM(_load_key()).decrypt(nonce, ciphertext, aad.encode() or None).decode()
