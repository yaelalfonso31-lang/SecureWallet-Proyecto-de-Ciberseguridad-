# Inicia el servicio Wallet en el puerto 8001 (usa python -m para evitar el bloqueo de uvicorn.exe).
# Uso, desde la carpeta backend:   powershell -ExecutionPolicy Bypass -File .\run_wallet.ps1
& .\.venv\Scripts\python.exe -m uvicorn wallet_service.main:app --host 0.0.0.0 --port 8001 --reload
