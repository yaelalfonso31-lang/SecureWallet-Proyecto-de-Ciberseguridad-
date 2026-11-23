@echo off
REM Preparación inicial del backend Wallet (una sola vez). Ejecutar desde la carpeta backend.
if not exist .venv python -m venv .venv
.venv\Scripts\python.exe -m pip install --upgrade pip
.venv\Scripts\python.exe -m pip install -r requirements.txt
if not exist .env .venv\Scripts\python.exe scripts\generate_env.py
.venv\Scripts\python.exe -m pytest -q
echo Listo. Para iniciar el servidor ejecuta run_wallet.bat
