# Mapa de sitio (pantallas)

Estado: ✅ ya existe en el proyecto · 🔲 por construir / opcional

## Acceso
- ✅ Login · ✅ Registro · 🔲 Splash + verificación root/jailbreak · 🔲 Onboarding · 🔲 Verificación OTP · 🔲 Configurar PIN/biometría · 🔲 2FA (TOTP) · 🔲 Recuperar contraseña · 🔲 Cuenta bloqueada

## Wallet (Equipo Wallet)
- 🔲 Dashboard (saldo, accesos rápidos, alertas)
- ✅ Lista de tarjetas · 🔲 Agregar / detalle (con biometría) / editar / bloquear / predeterminada
- 🔲 Cuentas bancarias vinculadas (lista, vincular, desvincular)
- 🔲 Enviar · Recibir (QR firmado) · Recargar · Retirar · Confirmación + comprobante firmado
- 🔲 Historial (filtros, detalle, verificar comprobante, exportar PDF firmado) · 🔲 Contactos

## Banco (Equipo Banco)
- ✅ Tablero principal del Banco y lista de promociones (`bank_page.dart`)
- ✅ Detalle y canje biométrico de promoción (`promotion_detail_page.dart`)
- ✅ Resumen de cuenta, saldo y movimientos (`account_page.dart`)
- ✅ Transferencias banco ↔ wallet: recargas y retiros (`transfer_page.dart`)
- ✅ Vinculación de cuenta OAuth2 + PKCE y apertura de cuenta demo (`bank_link_page.dart`)
- ✅ Panel admin en app (gestionado vía Swagger `/docs` y CLI `bank_admin.py`)
- 🔲 Notificaciones 

## Tienda (Equipo Tienda)
- ✅ Catálogo · 🔲 Detalle · 🔲 Búsqueda/filtros · 🔲 Carrito + cupones
- 🔲 Checkout "Pagar con Wallet" (autorización biométrica) · 🔲 Confirmación/error
- 🔲 Mis pedidos + recibo firmado · 🔲 Panel admin (opcional)

## Seguridad y perfil (Equipo Wallet + arquitecto)
- 🔲 Perfil · cambiar contraseña/PIN
- 🔲 Centro de seguridad: 2FA, biometría, dispositivos/sesiones, bitácora de accesos, límites, bloqueo de emergencia
- 🔲 Configuración, privacidad (exportar/eliminar cuenta), ayuda · ✅ Cerrar sesión · 🔲 Cierre por inactividad
- 🔲 Pantallas de apoyo: sin conexión, error, sesión expirada, mantenimiento, actualización obligatoria
