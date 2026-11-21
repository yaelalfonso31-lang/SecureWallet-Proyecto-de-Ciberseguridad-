"""Pruebas para mTLS Tienda -> Banco (B7).

Verifica la generación de la CA y los certificados, extensiones requeridas (SAN, EKU),
la validación de firmas criptográficas y el comportamiento del cliente bank_client.py.
"""
import ipaddress
from pathlib import Path
from unittest.mock import MagicMock, patch

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.x509.oid import ExtendedKeyUsageOID, ExtensionOID

from scripts.make_certs import generate_certs
from shared.config import settings
from store_service.bank_client import _resolve_cert_path, process_payment


def test_certificates_generation_and_extensions(tmp_path: Path):
    """Verifica que make_certs genere certificados válidos con SAN y EKU requeridos."""
    generate_certs(tmp_path)

    ca_pem = (tmp_path / "ca.pem").read_bytes()
    bank_pem = (tmp_path / "bank.pem").read_bytes()
    store_pem = (tmp_path / "store.pem").read_bytes()

    ca_cert = x509.load_pem_x509_certificate(ca_pem)
    bank_cert = x509.load_pem_x509_certificate(bank_pem)
    store_cert = x509.load_pem_x509_certificate(store_pem)

    # 1. Validar CA
    assert ca_cert.subject == ca_cert.issuer
    bc = ca_cert.extensions.get_extension_for_oid(ExtensionOID.BASIC_CONSTRAINTS).value
    assert bc.ca is True

    # 2. Validar que la CA firmó bank_cert y store_cert
    ca_pub = ca_cert.public_key()
    ca_pub.verify(
        bank_cert.signature,
        bank_cert.tbs_certificate_bytes,
        padding.PKCS1v15(),
        bank_cert.signature_hash_algorithm,
    )
    ca_pub.verify(
        store_cert.signature,
        store_cert.tbs_certificate_bytes,
        padding.PKCS1v15(),
        store_cert.signature_hash_algorithm,
    )

    # 3. Validar SubjectAlternativeName del Banco (DNS:localhost, DNS:bank, IP:127.0.0.1)
    san = bank_cert.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME).value
    dns_names = san.get_values_for_type(x509.DNSName)
    ip_addrs = san.get_values_for_type(x509.IPAddress)
    assert "localhost" in dns_names
    assert "bank" in dns_names
    assert ipaddress.IPv4Address("127.0.0.1") in ip_addrs

    # 4. Validar EKU de Servidor para el Banco
    bank_eku = bank_cert.extensions.get_extension_for_oid(ExtensionOID.EXTENDED_KEY_USAGE).value
    assert ExtendedKeyUsageOID.SERVER_AUTH in bank_eku

    # 5. Validar EKU de Cliente para la Tienda
    store_eku = store_cert.extensions.get_extension_for_oid(ExtensionOID.EXTENDED_KEY_USAGE).value
    assert ExtendedKeyUsageOID.CLIENT_AUTH in store_eku


def test_bank_client_uses_mtls_on_https():
    """Verifica que bank_client configure cert y verify cuando bank_url es https."""
    fake_payload = {"order_id": "ord_123", "amount_cents": 5000}
    fake_response = MagicMock(status_code=200)

    with patch.object(settings, "bank_url", "https://bank:8002"):
        with patch("store_service.bank_client.httpx.post", return_value=fake_response) as mock_post:
            resp = process_payment(fake_payload)
            assert resp.status_code == 200
            mock_post.assert_called_once()
            _, kwargs = mock_post.call_args

            assert "cert" in kwargs
            store_cert, store_key = kwargs["cert"]
            assert store_cert.endswith("store.pem")
            assert store_key.endswith("store.key")
            assert kwargs["verify"].endswith("ca.pem")
            assert kwargs["headers"]["X-API-Key"] == settings.bank_api_key


def test_bank_client_http_backward_compatibility():
    """Verifica que bank_client no fuerce certs en HTTP simple (compatibilidad tests legacy)."""
    fake_payload = {"order_id": "ord_123", "amount_cents": 5000}
    fake_response = MagicMock(status_code=200)

    with patch.object(settings, "bank_url", "http://localhost:8002"):
        with patch("store_service.bank_client.httpx.post", return_value=fake_response) as mock_post:
            resp = process_payment(fake_payload)
            assert resp.status_code == 200
            mock_post.assert_called_once()
            _, kwargs = mock_post.call_args
            assert "cert" not in kwargs
            assert "verify" not in kwargs


def test_resolve_cert_path(tmp_path: Path):
    """Verifica que _resolve_cert_path resuelva rutas existentes y maneje fallback."""
    # 1. Probar con un archivo temporal real
    dummy_cert = tmp_path / "dummy_ca.pem"
    dummy_cert.write_text("test")
    resolved = _resolve_cert_path(str(dummy_cert))
    assert Path(resolved).exists()
    assert resolved.endswith("dummy_ca.pem")

    # 2. Si el archivo no existe, devuelve el string original sin romper
    non_existent = "non_existent_certs/ca.pem"
    assert _resolve_cert_path(non_existent) == non_existent
