"""Genera la CA interna y los certificados mTLS para Tienda -> Banco (B7).

Multiplataforma (Python puro con cryptography). No depende de OpenSSL instalado.

Uso (desde la carpeta backend/):
    python scripts/make_certs.py
"""
import ipaddress
from datetime import datetime, timedelta, timezone
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


def generate_certs(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc)
    one_year = now + timedelta(days=365)

    print("==> Generando CA del proyecto...")
    ca_key = rsa.generate_private_key(public_exponent=65537, key_size=4096)
    ca_name = x509.Name([
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "SecureWallet"),
        x509.NameAttribute(NameOID.COMMON_NAME, "SecureWallet Root CA"),
    ])
    ca_cert = (
        x509.CertificateBuilder()
        .subject_name(ca_name)
        .issuer_name(ca_name)
        .public_key(ca_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(one_year)
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=True,
                crl_sign=True,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .sign(ca_key, hashes.SHA256())
    )

    print("==> Generando certificado del servidor Banco...")
    bank_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    bank_name = x509.Name([
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "SecureWallet"),
        x509.NameAttribute(NameOID.COMMON_NAME, "bank"),
    ])
    bank_cert = (
        x509.CertificateBuilder()
        .subject_name(bank_name)
        .issuer_name(ca_cert.subject)
        .public_key(bank_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(one_year)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName("localhost"),
                x509.DNSName("bank"),
                x509.IPAddress(ipaddress.IPv4Address("127.0.0.1")),
            ]),
            critical=False,
        )
        .add_extension(
            x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]),
            critical=False,
        )
        .sign(ca_key, hashes.SHA256())
    )

    print("==> Generando certificado de cliente de la Tienda...")
    store_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    store_name = x509.Name([
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "SecureWallet"),
        x509.NameAttribute(NameOID.COMMON_NAME, "store"),
    ])
    store_cert = (
        x509.CertificateBuilder()
        .subject_name(store_name)
        .issuer_name(ca_cert.subject)
        .public_key(store_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(one_year)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CLIENT_AUTH]),
            critical=False,
        )
        .sign(ca_key, hashes.SHA256())
    )

    # Guardar claves privadas y certificados
    def _save_key(key: rsa.RSAPrivateKey, filename: str) -> None:
        path = output_dir / filename
        path.write_bytes(
            key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption(),
            )
        )
        try:
            path.chmod(0o600)
        except OSError:
            pass

    def _save_cert(cert: x509.Certificate, filename: str) -> None:
        path = output_dir / filename
        path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
        try:
            path.chmod(0o644)
        except OSError:
            pass

    _save_key(ca_key, "ca.key")
    _save_cert(ca_cert, "ca.pem")

    _save_key(bank_key, "bank.key")
    _save_cert(bank_cert, "bank.pem")

    _save_key(store_key, "store.key")
    _save_cert(store_cert, "store.pem")

    print(f"==> Certificados creados en: {output_dir.resolve()}")


if __name__ == "__main__":
    certs_dir = Path(__file__).resolve().parents[1] / "certs"
    generate_certs(certs_dir)
