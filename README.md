# SecureWallet

Monedero digital (Wallet) para el proyecto de **Ciberseguridad**: app móvil en **Flutter** y backend en **Python FastAPI**, con un **Banco simulado** y una **Tienda online simulada**. El objetivo es demostrar el uso de cifrado, hash, firma electrónica y comunicación/transacciones seguras.

> ⚠️ Proyecto académico. Usa únicamente datos de prueba (tarjeta de prueba `4111 1111 1111 1111`). Nunca datos reales.

## Equipos

| Módulo | Personas | Mobile (`mobile/lib/features/`) | Backend (`backend/`) |
|---|---|---|---|
| Wallet | 3 | `wallet/` | `wallet_service/` (puerto 8001) |
| Banco simulado | 3 | `bank/` | `bank_service/` (puerto 8002) |
| Tienda simulada | 2 | `store/` | `store_service/` (puerto 8003) |
| Núcleo de seguridad | arquitecto (1 del equipo Wallet) | `mobile/lib/core/` | `backend/shared/` |

## Arquitectura (resumen)

```
App Flutter ──HTTPS──► Wallet Service ──firma Ed25519──┐
     │                                                  ▼
     ├────────HTTPS──► Tienda Service ──orden firmada──► Banco Service
     └────────HTTPS──► Banco Service        ◄──recibo firmado Ed25519──┘
```

Detalle y diagrama de secuencia del pago en [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md).

## Inicio rápido

### 1. Backend

```bash
cd backend
python -m venv .venv
# Windows (PowerShell): .venv\Scripts\Activate.ps1      Mac/Linux: source .venv/bin/activate
pip install -r requirements.txt

python scripts/generate_env.py      # crea .env con secretos y llaves aleatorias (NO se sube a Git)
python -m pytest -q                 # debe pasar todo

# Un servicio por terminal:
uvicorn wallet_service.main:app --port 8001 --reload
uvicorn bank_service.main:app   --port 8002 --reload
uvicorn store_service.main:app  --port 8003 --reload
```

Documentación interactiva: http://localhost:8001/docs · :8002/docs · :8003/docs

Alternativa con Docker (PostgreSQL + los 3 servicios): `docker compose up --build` (requiere `backend/.env`).

### 2. App móvil

Ver [`mobile/README.md`](mobile/README.md) (incluye `flutter create .` para generar `android/` e `ios/`).

## Qué ya está implementado

- **Wallet:** registro, login con Argon2id, bloqueo por intentos fallidos, JWT de vida corta, tarjetas (validación Luhn, número cifrado con AES-256-GCM, token en lugar del PAN, sin CVV), firma de órdenes de pago con Ed25519, bitácora con hashes encadenados.
- **Banco:** promociones, procesamiento de pagos que verifica firma, frescura (anti-replay por tiempo), unicidad (nonce/order_id), fondos, y emite **recibo firmado**.
- **Tienda:** catálogo, órdenes, pago con Wallet verificando el recibo firmado del Banco.
- **App:** login, registro, tarjetas, promociones, catálogo; almacenamiento seguro del token; verificador de firmas Ed25519 en Dart.
- **Pruebas:** 25 pruebas automáticas del backend (incluye flujo completo Wallet → Tienda → Banco).

## Pendientes por equipo

Consulta [`docs/BACKLOG_INICIAL.md`](docs/BACKLOG_INICIAL.md).

## Flujo de trabajo en Git

- `main` (protegida, entregas) ← `develop` (integración) ← `feature/<modulo>-<tarea>`.
- Todo cambio entra por Pull Request con 1 revisión; el CI debe estar en verde.
- Commits: `feat(wallet): ...`, `fix(bank): ...`, `security(shared): ...`, `docs: ...`, `test: ...`.
- Cada equipo trabaja en su carpeta; `core/` y `shared/` solo con revisión del arquitecto de seguridad.
- Secretos: solo en `.env` local. Compartan `.env.example`, nunca `.env`.
