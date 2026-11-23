"""Pruebas de controles de seguridad: 2FA TOTP, bitácora SHA-256, rate limiting y mTLS en tickets."""
from unittest.mock import MagicMock, patch

import pyotp
import secrets 

from unittest.mock import MagicMock, patch

from shared.config import settings
from shared.http import _REQUEST_LOG
from store_service.bank_client import redeem_tickets
from tests.helpers import register_and_login
from wallet_service.database import SessionLocal
from wallet_service.models import AuditLog


def test_2fa_totp_full_lifecycle(wallet_client):
    password = "Aa1-" + secrets.token_urlsafe(12)
    email, headers = register_and_login(wallet_client, password=password)

    # 1) Configurar 2FA
    setup = wallet_client.post("/security/2fa/setup", headers=headers)
    assert setup.status_code == 200, setup.text
    secret = setup.json()["secret"]
    assert "otpauth://totp/SecureWallet:" in setup.json()["provisioning_uri"]

    # 2) Rechaza código erróneo y activa con código válido
    assert wallet_client.post("/security/2fa/enable", json={"code": "000000"}, headers=headers).status_code == 400
    valid_code = pyotp.TOTP(secret).now()
    en = wallet_client.post("/security/2fa/enable", json={"code": valid_code}, headers=headers)
    assert en.status_code == 200 and en.json()["totp_enabled"] is True

    # 3) El login ahora exige código TOTP
    no_code = wallet_client.post("/auth/login", json={"email": email, "password": password})
    assert no_code.status_code == 401 and "2FA" in no_code.json()["detail"]

    with_code = wallet_client.post(
        "/auth/login",
        json={"email": email, "password": password, "totp_code": pyotp.TOTP(secret).now()},
    )
    assert with_code.status_code == 200


def test_audit_endpoint_reports_chain_integrity(wallet_client):
    _, headers = register_and_login(wallet_client)

    res = wallet_client.get("/security/audit", headers=headers)
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["chain_valid"] is True
    assert any(e["event"] == "register" for e in data["entries"])

    # Simular manipulación directa en BD y comprobar que GET /security/audit lo detecta
    with SessionLocal() as db:
        first = db.get(AuditLog, 1)
        original_detail = first.detail
        first.detail = "alterado_por_atacante"
        db.commit()

    tampered_res = wallet_client.get("/security/audit", headers=headers).json()
    assert tampered_res["chain_valid"] is False

    # Restaurar cadena para no afectar otras pruebas
    with SessionLocal() as db:
        first = db.get(AuditLog, 1)
        first.detail = original_detail
        db.commit()


def test_rate_limiting_blocks_burst_with_429(wallet_client, monkeypatch):
    _REQUEST_LOG.clear()
    monkeypatch.setattr(settings, "rate_limit_per_minute", 3)
    try:
        for _ in range(3):
            assert wallet_client.get("/health").status_code == 200
        blocked = wallet_client.get("/health")
        assert blocked.status_code == 429
    finally:
        _REQUEST_LOG.clear()


def test_redeem_tickets_uses_mtls_on_https():
    fake_response = MagicMock(status_code=200)
    with patch.object(settings, "bank_url", "https://bank:8002"):
        with patch("store_service.bank_client.httpx.post", return_value=fake_response) as mock_post:
            resp = redeem_tickets({"order_id": "ord_1"})
            assert resp.status_code == 200
            _, kwargs = mock_post.call_args
            assert "cert" in kwargs and "verify" in kwargs