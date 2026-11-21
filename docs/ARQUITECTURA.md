# Arquitectura

## Componentes

| Componente | Tecnología | Puerto | Responsabilidad |
|---|---|---|---|
| App móvil | Flutter | — | UI unificada de Wallet, Banco y Tienda |
| Wallet Service | FastAPI + SQLAlchemy | 8001 | Usuarios, sesiones, tarjetas cifradas, firma de órdenes y aserciones |
| Bank Service (simulado) | FastAPI | 8002 | Promociones, cuentas, validación de pagos, transferencias y recibos firmados |
| Store Service (simulada) | FastAPI | 8003 | Catálogo, órdenes, cobro vía Banco con cliente mTLS |
| Base de datos | SQLite (dev) / PostgreSQL (docker) | 5432 | Una base de datos independiente por servicio |

---

## Llaves y secretos

| Secreto / Certificado | Dónde vive | Para qué |
|---|---|---|
| `JWT_SECRET` | Wallet (:8001) | Firmar y verificar tokens de sesión de la Wallet |
| `BANK_JWT_SECRET` | Banco (:8002) | Firmar y verificar tokens de clientes del Banco (`aud="bank"`, scopes: `accounts:read`, `promotions:read`, `promotions:redeem`, `transfers:write`, `admin`). Distinto de `JWT_SECRET`. |
| `DATA_ENCRYPTION_KEY` | Wallet | Cifrar números de tarjeta (PAN) en reposo mediante AES-256-GCM (32 bytes en base64url) |
| Par Ed25519 **Wallet** | Privada: Wallet · Pública: Banco | La Wallet firma órdenes de pago (`/payments/authorize`), comprobantes de retiro y aserciones de vinculación |
| Par Ed25519 **Banco** | Privada: Banco · Pública: Tienda y App | El Banco firma recibos de compra aprobados y comprobantes de recarga (`to_wallet`) |
| `BANK_API_KEY` | Banco y Tienda | Cabecera `X-API-Key` para autenticación de servicio a servicio |
| CA interna (`ca.pem`, `ca.key`) | Entorno / Certs | Autoridad Certificadora raíz (`CN=SecureWallet Root CA`) que firma los certificados mTLS |
| Certificado Banco (`bank.pem`, `bank.key`) | Banco (:8002) | Certificado TLS de servidor con extensiones SAN (`DNS:localhost`, `DNS:bank`, `IP:127.0.0.1`) |
| Certificado Tienda (`store.pem`, `store.key`) | Tienda (:8003) | Certificado de cliente (`CN=store`, EKU `clientAuth`) exigido por el Banco en el canal mTLS |

---

## Diagramas de secuencia y flujos de seguridad

### 1. Flujo de pago y cobro con mTLS (B7)

```mermaid
sequenceDiagram
    participant A as App Flutter
    participant T as Tienda (:8003)
    participant W as Wallet (:8001)
    participant B as Banco (:8002)

    A->>T: POST /orders (crear orden con carrito)
    T-->>A: order_id, monto, comercio
    A->>A: Autenticación biométrica local
    A->>W: POST /payments/authorize (JWT Wallet)
    W-->>A: Orden {nonce, timestamp} + firma Ed25519
    A->>T: POST /orders/{id}/pay (orden firmada)
    Note over T,B: Canal mTLS (Handshake mutuo con certificados de la CA)
    T->>B: POST /transactions/process [X-API-Key + Certificado cliente store.pem]
    B->>B: Verifica cert cliente TLS, API key, firma Wallet, frescura (≤120s), nonce único y fondos
    B->>B: Aplica canje de promociones si existe y genera movimiento inmutable
    B-->>T: Recibo firmado con Ed25519 del Banco
    T->>T: Verifica firma del recibo con llave pública del Banco
    T-->>A: Pago confirmado + recibo firmado
    A->>A: (Opcional) Verificación local de recibo con ReceiptVerifier
```

---

### 2. Vinculación de Cuenta Bancaria (OAuth2 + PKCE + Aserción Wallet) (B2)

```mermaid
sequenceDiagram
    participant A as App Flutter
    participant W as Wallet (:8001)
    participant B as Banco (:8002)

    Note over A: 1. Genera code_verifier (32 bytes urlsafe)<br/>y code_challenge = S256(verifier)
    A->>W: POST /bank-link/assertion (JWT Wallet)
    W->>W: Genera assertion {wallet_user_id, nonce, timestamp, aud="bank"}
    W-->>A: Assertion + firma Ed25519 de la Wallet
    A->>B: POST /oauth/authorize (Email, Password, code_challenge, wallet_assertion)
    B->>B: Valida contraseña (Argon2id) y lockout por intentos
    B->>B: Valida firma Ed25519 de assertion, audience=="bank" y timestamp ≤ 120s
    B->>B: Guarda code_hash y challenge (vigencia 60s)
    B-->>A: Authorization code (un solo uso)
    A->>B: POST /oauth/token (code, code_verifier, client_id)
    B->>B: Comprueba SHA256(verifier) == challenge guardado
    B->>B: Quema el código (un solo uso) y vincula owner_ref = wallet_user_id
    B-->>A: Access Token del Banco (JWT con aud="bank")
```

---

### 3. Transferencias Banco ↔ Wallet (B5)

```mermaid
sequenceDiagram
    participant A as App Flutter
    participant W as Wallet (:8001)
    participant B as Banco (:8002)

    rect rgb(240, 248, 255)
    Note over A,B: A) Recarga (Banco → Wallet)
    A->>B: POST /transfers/to-wallet (JWT Banco, monto, idempotency_key)
    B->>B: Valida saldo, límite diario acumulado e idempotencia
    B->>B: Descuenta fondos y crea Movement
    B-->>A: Comprobante {voucher: {transfer_id, to_wallet, amount}, signature Banco Ed25519}
    A->>W: POST /wallet/topup (JWT Wallet, voucher, signature)
    W->>W: Valida firma Banco, destino to_wallet, vigencia (≤3600s) y unicidad por transfer_id
    W-->>A: Recarga acreditada en saldo Wallet
    end

    rect rgb(255, 245, 238)
    Note over A,B: B) Retiro (Wallet → Banco)
    A->>W: POST /wallet/withdraw (JWT Wallet, monto)
    W->>W: Valida saldo, descuenta y genera comprobante firmado Ed25519
    W-->>A: Comprobante {voucher: {from_wallet, amount, nonce}, signature Wallet Ed25519}
    A->>B: POST /transfers/from-wallet (JWT Banco, voucher, signature)
    B->>B: Valida firma Wallet, frescura (≤120s), nonce único y que voucher pertenezca al dueño
    B->>B: Acredita fondos en cuenta bancaria y crea Movement
    B-->>A: Retiro completado exitosamente
    end
```

---

## Controles de seguridad por capa

- **Identidad y Acceso:**
  - Contraseñas protegidas con **Argon2id**.
  - Bloqueo de cuenta tras 5 intentos fallidos durante 15 minutos (`lockout_minutes`).
  - Tokens JWT separados con audiencias estrictas (`aud="wallet"` vs `aud="bank"`).
  - Autorización en Banco basada en scopes y comprobación del rol `admin` directamente en la base de datos (anti-elevación de privilegios).
  - Vinculación Wallet ↔ Banco con **OAuth2 Authorization Code + PKCE S256** (RFC 7636) y aserciones firmadas por la Wallet.
- **Datos en reposo:**
  - Cifrado simétrico autenticado **AES-256-GCM** para PAN de tarjetas, con datos autenticados asociados (AAD) vinculados al usuario.
  - Tokenización de tarjetas sin almacenamiento de códigos CVV.
- **Integridad y no repudio:**
  - Firmas digitales **Ed25519** sobre representaciones canónicas JSON (RFC 8785) para órdenes de pago, recibos de compra y comprobantes de transferencias.
  - Bitácora inmutable en movimientos y transferencias; hash encadenado en la Wallet.
- **Protección Anti-Replay e Idempotencia:**
  - Parámetros `nonce` aleatorios criptográficos y ventanas de frescura de 120 segundos.
  - Claves de idempotencia (`idempotency_key`) y restricciones de unicidad (`UNIQUE`) en bases de datos para pagos, canjes de promociones y transferencias.
- **Seguridad en transporte y canal entre servicios:**
  - **mTLS obligatorio** entre Tienda y Banco: el servidor Banco exige certificado de cliente (`--ssl-cert-reqs 2`) firmado por la CA del proyecto y la Tienda valida el certificado del Banco con la CA.
  - Cabecera `X-API-Key` como defensa en profundidad.
- **Seguridad en la App móvil:**
  - Claves y tokens de sesión gestionados de forma segura.
  - Confirmación biométrica (`LocalAuthentication`) para acciones sensibles: canje de promociones, autorización de pagos y transferencias.
