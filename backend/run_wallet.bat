@echo off
REM Inicia el servicio Wallet en el puerto 8001. Ejecutar desde la carpeta backend.
.venv\Scripts\python.exe -m uvicorn wallet_service.main:app --host 0.0.0.0 --port 8001 --reload
