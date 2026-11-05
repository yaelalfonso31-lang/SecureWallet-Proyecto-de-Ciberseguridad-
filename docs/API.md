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
| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/promotions` | — | Bonos y promociones activas |
| GET | `/bank/public-key` | — | Clave pública Ed25519 del Banco |
| POST | `/transactions/process` | `X-API-Key` | Procesa orden firmada → `{receipt, signature}`. 400 firma/expirada, 402 fondos, 409 repetida |

## Tienda — `:8003`
| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/products`, `/products/{id}` | — | Catálogo |
| POST | `/orders` | — | Crea orden → `{order_id, merchant, amount_cents, currency}` |
| POST | `/orders/{id}/pay` | — | Recibe orden firmada, cobra vía Banco, verifica recibo |
| GET | `/orders/{id}` | — | Estado de la orden |

> TODO Tienda: asociar órdenes a usuarios (hoy `/orders` es público para simplificar).
