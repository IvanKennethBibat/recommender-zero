from argon2 import PasswordHasher
from fastapi.testclient import TestClient

from app import user_routes
from app.auth import (
    DUMMY_PASSWORD_HASH,
    hash_password,
    password_needs_rehash,
    verify_password,
)
from app.main import app

# Hash created by passlib before it was removed, to keep existing users' passwords working
PASSLIB_HASH = "$argon2id$v=19$m=65536,t=3,p=4$CUFo7f3fm3POmdPauzdmjA$xHk+oDqilrZM2oVmqmtCViwDiBTZYTUaqfFsIhmRk6w"


def test_hash_and_verify():
    hashed = hash_password("Secret!pass")
    assert hashed.startswith("$argon2id$")
    assert verify_password("Secret!pass", hashed)
    assert not verify_password("wrong", hashed)


def test_verifies_passlib_hash():
    assert verify_password("OldUser!pass", PASSLIB_HASH)
    assert not verify_password("wrong", PASSLIB_HASH)


def test_invalid_hash_returns_false():
    assert not verify_password("anything", "not-a-hash")


def test_needs_rehash_for_weaker_parameters():
    weak_hash = PasswordHasher(time_cost=1, memory_cost=8192).hash("Secret!pass")
    assert password_needs_rehash(weak_hash)
    assert not password_needs_rehash(hash_password("Secret!pass"))


client = TestClient(app)


def test_register_duplicate_username_returns_400():
    payload = {"username": "dupuser", "password": "DupPassword!"}
    client.post("/register", json=payload)
    response = client.post("/register", json=payload)
    assert response.status_code == 400
    assert response.json()["detail"] == "Username already exists"


def test_login_unknown_user_still_verifies_a_hash(monkeypatch):
    calls = []

    def spy(plain_password, hashed_password):
        calls.append(hashed_password)
        return False

    monkeypatch.setattr(user_routes, "verify_password", spy)
    response = client.post("/login", data={"username": "no-such-user", "password": "Whatever!1"})
    assert response.status_code == 401
    assert calls == [DUMMY_PASSWORD_HASH]


def test_docs_disabled_by_default():
    assert client.get("/docs").status_code == 404
    assert client.get("/redoc").status_code == 404
    assert client.get("/openapi.json").status_code == 404
