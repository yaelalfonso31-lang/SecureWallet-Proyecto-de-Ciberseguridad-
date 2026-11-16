# Preparación inicial del backend Wallet (una sola vez).
# Uso, desde la carpeta backend:   powershell -ExecutionPolicy Bypass -File .\setup.ps1
$ErrorActionPreference = "Stop"

if (-not (Test-Path ".venv")) { python -m venv .venv }
$py = ".\.venv\Scripts\python.exe"

& $py -m pip install --upgrade pip
& $py -m pip install -r requirements.txt

if (-not (Test-Path ".env")) { & $py scripts\generate_env.py } else { Write-Host ".env ya existe, no se sobreescribe." }

Write-Host "Ejecutando pruebas..."
& $py -m pytest -q
Write-Host "Listo. Para iniciar el servidor:  powershell -ExecutionPolicy Bypass -File .\run_wallet.ps1"
