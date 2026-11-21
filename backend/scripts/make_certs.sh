#!/usr/bin/env bash
# Genera la CA interna y los certificados mTLS para Tienda -> Banco (B7).
# Uso (desde la carpeta backend/):
#     bash scripts/make_certs.sh
# O desde la raíz del proyecto:
#     bash backend/scripts/make_certs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CERTS_DIR="${BACKEND_DIR}/certs"

mkdir -p "${CERTS_DIR}"
cd "${CERTS_DIR}"

echo "==> Generando CA del proyecto..."
openssl req -x509 -newkey rsa:4096 -days 365 -nodes \
    -keyout ca.key -out ca.pem \
    -subj "/CN=SecureWallet Root CA/O=SecureWallet"

echo "==> Generando certificado del servidor Banco..."
openssl req -newkey rsa:2048 -nodes \
    -keyout bank.key -out bank.csr \
    -subj "/CN=bank/O=SecureWallet"

cat <<EOF > bank_ext.cnf
basicConstraints = CA:FALSE
nsCertType = server
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = bank
IP.1 = 127.0.0.1
EOF

openssl x509 -req -in bank.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
    -out bank.pem -days 365 -extfile bank_ext.cnf

echo "==> Generando certificado de cliente de la Tienda..."
openssl req -newkey rsa:2048 -nodes \
    -keyout store.key -out store.csr \
    -subj "/CN=store/O=SecureWallet"

cat <<EOF > store_ext.cnf
basicConstraints = CA:FALSE
nsCertType = client
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

openssl x509 -req -in store.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
    -out store.pem -days 365 -extfile store_ext.cnf

# Limpiar archivos temporales
rm -f bank.csr store.csr bank_ext.cnf store_ext.cnf

chmod 600 *.key *.pem || true

echo "==> Certificados generados exitosamente en ${CERTS_DIR}:"
ls -la "${CERTS_DIR}"
