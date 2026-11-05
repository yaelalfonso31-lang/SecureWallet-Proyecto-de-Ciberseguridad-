"""Firma electrónica con Ed25519 sobre JSON canónico."""
import base64
import json

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode()


def generate_keypair() -> tuple[str, str]:
    """Devuelve (clave_privada, clave_pública) en base64url."""
    private = Ed25519PrivateKey.generate()
    private_bytes = private.private_bytes(
        serialization.Encoding.Raw,
        serialization.PrivateFormat.Raw,
        serialization.NoEncryption(),
    )
    public_bytes = private.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    )
    return _b64(private_bytes), _b64(public_bytes)


def canonical_json(obj) -> bytes:
    """Serialización determinista: ambas partes deben firmar/verificar los mismos bytes.

    La app Flutter implementa la misma regla (ver mobile/lib/core/security/receipt_verifier.dart).
    """
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def sign(private_key_b64: str, payload: dict) -> str:
    if not private_key_b64:
        raise RuntimeError("Falta la clave privada de firma (ver scripts/generate_env.py)")
    key = Ed25519PrivateKey.from_private_bytes(base64.urlsafe_b64decode(private_key_b64))
    return _b64(key.sign(canonical_json(payload)))


def verify(public_key_b64: str, payload: dict, signature_b64: str) -> bool:
    if not public_key_b64:
        raise RuntimeError("Falta la clave pública de verificación")
    try:
        key = Ed25519PublicKey.from_public_bytes(base64.urlsafe_b64decode(public_key_b64))
        key.verify(base64.urlsafe_b64decode(signature_b64), canonical_json(payload))
        return True
    except (InvalidSignature, ValueError):
        return False
