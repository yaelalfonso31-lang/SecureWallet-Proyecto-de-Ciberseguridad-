import uuid


def register_and_login(client, password="ClaveSegura123"):
    email = f"{uuid.uuid4().hex[:10]}@example.com"
    r = client.post("/auth/register", json={"email": email, "full_name": "Ana Prueba", "password": password})
    assert r.status_code == 201, r.text
    r = client.post("/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return email, {"Authorization": f"Bearer {r.json()['access_token']}"}
