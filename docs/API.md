# Contrato de API (resumen)

La referencia completa y siempre actualizada está en `/docs` de cada servicio (OpenAPI). Si cambias un endpoint, actualiza esta tabla en el mismo PR.

## Wallet — `:8001`
| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| POST | `/auth/register` | — | Registro (contraseña ≥ 10, letras y números) |
| POST | `/auth/login` | — | Devuelve JWT. 401 credenciales, 423 cuenta bloqueada |
| GET | `/auth/me` | JWT | Perfil |
| POST | `/cards` | JWT | Agrega tarjeta (Luhn, cifrada, devuelve token y last4) |
| GET | `/cards` | JWT | Lista tarjetas (enmascaradas) |
| DELETE | `/cards/{id}` | JWT | Elimina tarjeta |
| POST | `/payments/authorize` | JWT | Devuelve `{order, signature}` firmado por la Wallet |
| GET | `/wallet/balance` | JWT | Saldo real de la Wallet `{balance_cents, currency}` (empieza en 0) |
| GET | `/wallet/movements` | JWT | Movimientos del saldo, desc por id (`limit` 1–100, cursor `before`) |
| POST | `/wallet/topup` | JWT | Abona una recarga: recibe el `{voucher, signature}` que firmó el Banco (`/transfers/to-wallet`). Verifica firma, dirección `to_wallet`, dueño y vigencia (`WALLET_VOUCHER_MAX_AGE_SECONDS`). **Idempotente** por `transfer_id`: reenviarlo responde `already_credited` sin abonar de nuevo. 400 firma/expirado, 403 de otro usuario |
| POST | `/wallet/withdraw` | JWT | Descuenta `amount_cents` y devuelve el `{voucher, signature}` `from_wallet` firmado por la Wallet para entregarlo a `/transfers/from-wallet`. 402 saldo insuficiente |

## Banco — `:8002`

Tabla de endpoints del Banco. Es el **contrato base (B0)** entre las dos personas del
equipo: los marcados como _(pendiente)_ aún no existen y se implementan en la tarea
indicada. Los tokens del Banco son JWT propios con `aud="bank"`, distintos de los de
la Wallet, y se envían como `Authorization: Bearer <token>`.

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/promotions` | — | Bonos y promociones activas |
| GET | `/bank/public-key` | — | Clave pública Ed25519 del Banco |
| POST | `/transactions/process` | `X-API-Key` + mTLS | Procesa orden firmada → `{receipt, signature}`. Requiere certificado de cliente TLS emitido por la CA interna (`CN=store`). 400 firma/expirada, 402 fondos, 403 cuenta congelada, 404 sin cuenta, 409 repetida. Cada cargo deja un `Movement`. Si hay canje pendiente, aplica el descuento y el recibo incluye `discount_cents`, `charged_cents` y `promotion_id` (`amount_cents` no cambia) |
| POST | `/oauth/authorize` | contraseña + aserción Wallet | Login + PKCE (`S256`) → `{code, state}`. Código de un solo uso, 60 s. 400 credenciales/aserción/`client_id`/método, 403 cuenta congelada, 409 usuario Wallet ya ligado a otra cuenta, 423 bloqueado |
| POST | `/oauth/token` | — | Canjea `code` + `code_verifier` + `client_id` → `{access_token, token_type, expires_in, scope}` y liga la cuenta (`owner_ref = wallet_user_id`). 400 código inválido/usado/expirado o verifier incorrecto (el código se invalida igual) |
| GET | `/accounts/me` | JWT Banco `accounts:read` | Saldo, número enmascarado (`•••• 1234`), moneda y estado de la cuenta del dueño del token. 401 sin token, 404 sin cuenta |
| GET | `/accounts/me/movements` | JWT Banco `accounts:read` | Movimientos del dueño, desc por id (`limit` 1–100, cursor `before`). Anti-IDOR: nunca hay rutas `/accounts/{id}` |
| GET | `/promotions/{id}` | — | Detalle de una promoción |
| GET | `/promotions/me/redemptions` | JWT Banco `promotions:read` | Canjes propios `[{promotion_id, title, discount_percent, redeemed_at, used_in_order_id, status}]`. `status`: `pending` (se aplicará en la próxima compra) o `used`. La app lo usa para saber qué ya canjeó |
| POST | `/promotions/{id}/redeem` | JWT Banco `promotions:redeem` | Canje de un solo uso. 400 vencida, 409 ya canjeada |
| POST | `/customers/open-account` | aserción Wallet | **Abre cliente y cuenta desde la app.** Body: `{email, password (≥10, letras y números), wallet_assertion}`. Crea la cuenta con `BANK_OPEN_ACCOUNT_BALANCE_CENTS` (por defecto $5,000 de demostración) y un movimiento de apertura. Después la app hace la vinculación normal (`/oauth/authorize` + `/oauth/token`). 400 aserción inválida/vencida, 409 el usuario Wallet ya tiene cuenta o el correo ya existe, 422 contraseña débil |
| POST | `/transfers/to-wallet` | JWT Banco `transfers:write` | Recarga a la Wallet → `{voucher, signature}` firmado por el Banco. Idempotente por `idempotency_key`. 402 fondos, 429 límite diario |
| POST | `/transfers/from-wallet` | JWT Banco `transfers:write` | Retiro desde la Wallet: verifica el comprobante firmado por la Wallet (firma, frescura, nonce y dueño) y abona. 400 firma/expirado, 403 otro dueño, 409 reenvío |
| GET | `/admin/promotions` | JWT Banco admin | Lista promociones incluidas las inactivas. 403 sin rol admin |
| POST | `/admin/promotions` | JWT Banco admin | Crea promoción. 422 validación de rangos |

| PATCH | `/admin/promotions/{id}` | JWT Banco admin | Edita o desactiva promoción. 404 si no existe |

### Vinculación Wallet ↔ Banco

`client_id` permitido: `securewallet-mobile`. El `code_challenge` es `BASE64URL(SHA256(code_verifier))`
sin relleno (43 caracteres); el `code_verifier` mide de 43 a 128 caracteres (RFC 7636).

`wallet_assertion` es la respuesta de `POST /bank-link/assertion` de la Wallet,
firmada con `WALLET_SIGNING_PRIVATE_KEY` sobre el JSON canónico de `assertion`:

```json
{
  "assertion": {"wallet_user_id": "<id del usuario>", "nonce": "<16-64 chars>", "timestamp": 1731200000, "audience": "bank"},
  "signature": "<Ed25519 base64url>"
}
```

El Banco exige firma válida, `audience == "bank"` y `timestamp` con menos de 120 s.

Para obtener un token de administrador en desarrollo: `python scripts/bank_admin.py --email admin@banco.com`
(imprime un token de 15 minutos para usarlo en `http://localhost:8002/docs` → Authorize).

### Canal seguro mTLS Tienda ↔ Banco (B7)

La comunicación interservicio entre la Tienda y el Banco (`POST /transactions/process`) está protegida por TLS Mutuo (mTLS), además de la cabecera `X-API-Key`.

1. **Generación de certificados:**
   ```bash
   # En Linux / Mac / Git Bash:
   bash scripts/make_certs.sh
   # O en Windows / cualquier entorno con Python:
   python scripts/make_certs.py
   ```
   Crea la CA interna y los certificados en `backend/certs/` (`ca.pem`, `bank.pem`, `bank.key`, `store.pem`, `store.key`).

2. **Arranque del Banco con mTLS:**
   ```bash
   uvicorn bank_service.main:app --port 8002 --ssl-keyfile certs/bank.key --ssl-certfile certs/bank.pem --ssl-ca-certs certs/ca.pem --ssl-cert-reqs 2
   ```

3. **Demostración de seguridad (Prueba de handshake):**
   - **Petición rechazada sin certificado de cliente:**
     ```bash
     curl https://localhost:8002/bank/public-key --cacert certs/ca.pem
     # Error esperado: el handshake TLS falla (el servidor Banco exige certificado de cliente y aborta la conexión).
     ```
   - **Petición autorizada con certificado de la Tienda:**
     ```bash
     curl https://localhost:8002/bank/public-key --cacert certs/ca.pem --cert certs/store.pem --key certs/store.key
     # Respuesta 200 OK con la clave pública Ed25519 del Banco.
     ```



## Tienda — `:8003`

Las rutas de órdenes usan el **JWT de la Wallet** (`Authorization: Bearer ...`): cada usuario solo ve y modifica sus propias órdenes.

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/products` | — | Catálogo. Filtros opcionales: `q` (nombre/descripción) y `category`. Cada producto trae `category` |
| GET | `/products/categories` | — | Lista de categorías |
| GET | `/products/{id}` | — | Detalle de un producto |
| POST | `/cart/quote` | JWT | Cotiza el carrito (subtotal, cupón, total) calculado en el servidor |
| POST | `/orders` | JWT | Crea orden → `{order_id, merchant, amount_cents, currency}` |
| GET | `/orders` | JWT | **Historial** del usuario, más recientes primero. `limit` 1–100 y `status` (`pending`/`paid`/`cancelled`). Incluye artículos con nombre, totales, `charged_cents`, `receipt` y `signature` |
| GET | `/orders/{id}` | JWT | Estado de una orden propia |
| POST | `/orders/{id}/pay` | JWT | Recibe la orden firmada por la Wallet, cobra vía Banco, verifica el recibo. 409 si ya está pagada o cancelada |
| POST | `/orders/{id}/cancel` | JWT | **Cancela** una orden pendiente. 409 si ya no está pendiente, 404 si no es tuya |
| POST | `/admin/products` | `X-Admin-Key` | Crea un producto. Deshabilitado (401) si `STORE_ADMIN_KEY` está vacío |
| PATCH | `/admin/products/{id}` | `X-Admin-Key` | Edita precio, existencias, categoría, etc. |

> Si tu `store.db` ya existía, la columna `products.category` se agrega sola al iniciar el servicio (`store_service/migrations.py`).
