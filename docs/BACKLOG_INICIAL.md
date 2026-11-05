# Backlog inicial por equipo (crear como Issues en GitHub)

Etiquetas sugeridas: `wallet`, `bank`, `store`, `security`, `mobile`, `backend`, `docs`.

## Núcleo de seguridad (arquitecto)
- [ ] Rate limiting (slowapi) en login y pagos
- [ ] TLS 1.3 local con certificados propios (`mkcert`/OpenSSL) y certificate pinning en Flutter
- [ ] mTLS Tienda ↔ Banco ↔ Wallet
- [ ] Rotación de claves y refresh tokens rotativos
- [ ] Completar `docs/THREAT_MODEL.md` y script de demos de ataque

## Wallet (3)
- [ ] 2FA TOTP (pyotp ya incluido) + pantalla de activación
- [ ] Pantalla "Agregar tarjeta" + eliminar + biometría antes de ver datos
- [ ] Re-autenticación obligatoria antes de `/payments/authorize`
- [ ] Saldo, recargas, historial de transacciones (modelo `Transaction`)
- [ ] Centro de seguridad: sesiones, dispositivos, bitácora visible
- [ ] Recuperación de contraseña con enlace firmado de un solo uso

## Banco (3)
- [ ] Cuentas y movimientos (endpoints + pantallas)
- [ ] Vinculación Wallet ↔ Banco con OAuth2 + PKCE (simulado)
- [ ] Canje de promociones y su efecto en el cobro
- [ ] Transferencias banco ↔ wallet
- [ ] Panel admin de promociones

## Tienda (2)
- [ ] Detalle de producto, carrito y cupones
- [ ] Checkout completo "Pagar con Wallet" (flujo en `docs/ARQUITECTURA.md`)
- [ ] Órdenes ligadas a usuario + historial de pedidos con recibo verificable
- [ ] Panel admin de productos
