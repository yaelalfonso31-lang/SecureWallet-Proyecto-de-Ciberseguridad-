# App móvil (Flutter)

Una sola app con tres módulos en `lib/features/` (wallet, bank, store) y un núcleo compartido en `lib/core/`.

## Primer arranque

El repositorio incluye `lib/`, `test/` y `pubspec.yaml`. Las carpetas de plataforma (`android/`, `ios/`) las genera Flutter:

## Ejecutar contra el backend local

```bash

# Teléfono físico en la misma red Wi-Fi
flutter run --dart-define=WALLET_URL=http://IP_DE_TU_PC:8001 \
            --dart-define=BANK_URL=http://IP_DE_TU_PC:8002 \
            --dart-define=STORE_URL=http://IP_DE_TU_PC:8003
```

## Estructura

```
lib/
├── main.dart, app.dart
├── core/                 # Lo toca solo el arquitecto de seguridad (PR revisado)
│   ├── config/           # URLs de servicios
│   ├── network/          # Dio + token JWT
│   ├── security/         # almacenamiento seguro, biometría, verificación de firmas
│   └── theme/
└── features/
    ├── wallet/           # Equipo Wallet  (login, registro, tarjetas, ...)
    ├── bank/             # Equipo Banco   (promociones, cuentas, ...)
    └── store/            # Equipo Tienda  (catálogo, carrito, checkout)
```
