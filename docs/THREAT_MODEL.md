# Modelo de amenazas (STRIDE) — punto de partida

Completar y mantener durante el proyecto. Cada fila debe terminar enlazada a una prueba o a una demo.

| STRIDE | Amenaza | Activo | Control actual | Pendiente / Demo |
|---|---|---|---|---|
| **S**poofing | Robo de credenciales / fuerza bruta | Cuenta de usuario | Argon2id, bloqueo tras 5 intentos | 2FA TOTP, rate limiting por IP |
| **S**poofing | Falsificar una orden de pago | Pagos | Firma Ed25519 de la Wallet | Demo: orden con firma ajena → 400 |
| **T**ampering | Alterar el monto de una orden | Pagos | Firma sobre JSON canónico | Demo: cambiar `amount_cents` → 400 |
| **T**ampering | Alterar la bitácora | Auditoría | Hash encadenado | Demo: editar un registro → `verify_chain` falla |
| **R**epudiation | "Yo no hice ese pago" | Pagos | Orden firmada + recibo firmado + bitácora | Exportar comprobante verificable |
| **I**nfo disclosure | Fuga de la BD con tarjetas | PAN | AES-256-GCM, tokenización, sin CVV | Rotación de claves, Vault |
| **I**nfo disclosure | Intercepción en la red (MITM) | Tráfico | (pendiente) TLS 1.3 | Certificate pinning + demo con mitmproxy |
| **D**enial of service | Inundar login/pagos | Disponibilidad | — | Rate limiting, límites de tamaño |
| **E**levation | Acceder a tarjetas de otro usuario | Datos | Validación de dueño en cada consulta | Pruebas de autorización (IDOR) |
| **E**levation | Tienda llamando al Banco sin permiso | Banco | `X-API-Key` | mTLS |
| Replay | Reenviar una orden capturada | Pagos | nonce + timestamp + UNIQUE | Demo: reenvío → 409 |
