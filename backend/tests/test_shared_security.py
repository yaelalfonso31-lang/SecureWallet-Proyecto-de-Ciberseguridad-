import pytest
from cryptography.exceptions import InvalidTag

from shared.security.crypto import decrypt, encrypt
from shared.security.hashing import chain_hash, sha256_hex
from shared.security.passwords import hash_password, verify_password
from shared.security.signing import generate_keypair, sign, verify
from shared.validators import luhn_valid


def test_password_hash_argon2id_and_verify():
    h = hash_password("ClaveSegura123")
    assert h.startswith("$argon2id$")
    assert verify_password(h, "ClaveSegura123")
    assert not verify_password(h, "otra-clave")


def test_aes_gcm_roundtrip_and_aad_binding():
    token = encrypt("4111111111111111", aad="user-1")
    assert "4111" not in token
    assert decrypt(token, aad="user-1") == "4111111111111111"
    with pytest.raises(InvalidTag):
        decrypt(token, aad="user-2")  # ligado a su dueño


def test_two_encryptions_differ_nonce():
    assert encrypt("hola") != encrypt("hola")


def test_sign_and_verify_detects_tampering():
    priv, pub = generate_keypair()
    payload = {"amount": 100, "to": "tienda"}
    sig = sign(priv, payload)
    assert verify(pub, payload, sig)
    assert not verify(pub, {"amount": 999, "to": "tienda"}, sig)


def test_sha256_and_hash_chain():
    assert sha256_hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    assert chain_hash("0" * 64, {"a": 1}) != chain_hash("0" * 64, {"a": 2})


def test_luhn():
    assert luhn_valid("4111111111111111")
    assert not luhn_valid("4111111111111112")
