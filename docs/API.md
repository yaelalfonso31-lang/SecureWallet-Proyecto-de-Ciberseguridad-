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

## Banco — `:8002`

Tabla de endpoints del Banco. Es el **contrato base (B0)** entre las dos personas del
equipo: los marcados como _(pendiente)_ aún no existen y se implementan en la tarea
indicada. Los tokens del Banco son JWT propios con `aud="bank"`, distintos de los de
la Wallet, y se envían como `Authorization: Bearer <token>`.

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/promotions` | — | Bonos y promociones activas |
| GET | `/bank/public-key` | — | Clave pública Ed25519 del Banco |
| POST | `/transactions/process` | `X-API-Key` | Procesa orden firmada → `{receipt, signature}`. 400 firma/expirada, 402 fondos, 403 cuenta congelada, 404 sin cuenta, 409 repetida. Cada cargo deja un `Movement`. Si hay canje pendiente, aplica el descuento y el recibo incluye `discount_cents`, `charged_cents` y `promotion_id` (`amount_cents` no cambia) |
| POST | `/oauth/authorize` | aserción Wallet | _(pendiente, B2)_ Login + PKCE → `{code, state}`. 400 credenciales/aserción, 423 bloqueado |
| POST | `/oauth/token` | — | _(pendiente, B2)_ Canjea `code` + `code_verifier` → `{access_token, scope}`. 400 código inválido/usado/expirado |
| GET | `/accounts/me` | JWT Banco `accounts:read` | Saldo, número enmascarado (`•••• 1234`), moneda y estado de la cuenta del dueño del token. 401 sin token, 404 sin cuenta |
| GET | `/accounts/me/movements` | JWT Banco `accounts:read` | Movimientos del dueño, desc por id (`limit` 1–100, cursor `before`). Anti-IDOR: nunca hay rutas `/accounts/{id}` |
| GET | `/promotions/{id}` | — | _(pendiente, B4-a)_ Detalle de una promoción |
| POST | `/promotions/{id}/redeem` | JWT Banco `promotions:redeem` | _(pendiente, B4-a)_ Canje de un solo uso. 400 vencida, 409 ya canjeada |
| POST | `/transfers/to-wallet` | JWT Banco `transfers:write` | Recarga a la Wallet → `{voucher, signature}` firmado por el Banco. Idempotente por `idempotency_key`. 402 fondos, 429 límite diario |
| POST | `/transfers/from-wallet` | JWT Banco `transfers:write` | Retiro desde la Wallet: verifica el comprobante firmado por la Wallet (firma, frescura, nonce y dueño) y abona. 400 firma/expirado, 403 otro dueño, 409 reenvío |
| GET | `/admin/promotions` | JWT Banco admin | _(pendiente, B6)_ Lista promociones incluidas las inactivas. 403 sin rol admin |
| POST | `/admin/promotions` | JWT Banco admin | _(pendiente, B6)_ Crea promoción. 422 validación de rangos |
| PATCH | `/admin/promotions/{id}` | JWT Banco admin | _(pendiente, B6)_ Edita o desactiva promoción |

## Tienda — `:8003`
| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/products`, `/products/{id}` | — | Catálogo |
| POST | `/orders` | — | Crea orden → `{order_id, merchant, amount_cents, currency}` |
| POST | `/orders/{id}/pay` | — | Recibe orden firmada, cobra vía Banco, verifica recibo |
| GET | `/orders/{id}` | — | Estado de la orden |

> TODO Tienda: asociar órdenes a usuarios (hoy `/orders` es público para simplificar).
