import hashlib
import hmac

from shared.security.signing import canonical_json


def sha256_hex(data: bytes | str) -> str:
    if isinstance(data, str):
        data = data.encode()
    return hashlib.sha256(data).hexdigest()


def hmac_sha256_hex(key: str, message: str) -> str:
    return hmac.new(key.encode(), message.encode(), hashlib.sha256).hexdigest()


def constant_time_equals(a: str, b: str) -> bool:
    return hmac.compare_digest(a, b)


def chain_hash(prev_hash: str, record: dict) -> str:
    """Hash encadenado: cada registro incluye el hash del anterior (bitácora a prueba de manipulación)."""
    return sha256_hex(prev_hash + canonical_json(record).decode())
