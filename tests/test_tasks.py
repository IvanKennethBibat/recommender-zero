import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


@pytest.fixture(scope="module")
def auth_headers():
    client.post("/register", json={"username": "testuser", "password": "TestPassword!"})
    response = client.post("/login", data={"username": "testuser", "password": "TestPassword!"})
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_create_task(auth_headers):
    response = client.post("/tasks", json={"title": "Test task"}, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["title"] == "Test task"
    assert response.json()["completed"] == False


def test_get_tasks(auth_headers):
    response = client.get("/tasks", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_get_task(auth_headers):
    create = client.post("/tasks", json={"title": "Get me"}, headers=auth_headers)
    task_id = create.json()["id"]
    response = client.get(f"/tasks/{task_id}", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["id"] == task_id


def test_update_task(auth_headers):
    create = client.post("/tasks", json={"title": "Update me"}, headers=auth_headers)
    task_id = create.json()["id"]
    response = client.patch(f"/tasks/{task_id}", json={"completed": True}, headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["completed"] == True


def test_delete_task(auth_headers):
    create = client.post("/tasks", json={"title": "Delete me"}, headers=auth_headers)
    task_id = create.json()["id"]
    client.delete(f"/tasks/{task_id}", headers=auth_headers)
    response = client.get(f"/tasks/{task_id}", headers=auth_headers)
    assert response.status_code == 404

def test_create_task_rejects_empty_and_long_titles(auth_headers):
    assert client.post("/tasks", json={"title": ""}, headers=auth_headers).status_code == 422
    assert client.post("/tasks", json={"title": "x" * 201}, headers=auth_headers).status_code == 422


def test_get_tasks_rejects_out_of_range_pagination(auth_headers):
    assert client.get("/tasks?limit=1000", headers=auth_headers).status_code == 422
    assert client.get("/tasks?limit=0", headers=auth_headers).status_code == 422
    assert client.get("/tasks?skip=-1", headers=auth_headers).status_code == 422


def test_register_rejects_invalid_usernames_and_long_passwords():
    assert client.post("/register", json={"username": "ab", "password": "TestPassword!"}).status_code == 422
    assert client.post("/register", json={"username": "bad name", "password": "TestPassword!"}).status_code == 422
    assert client.post("/register", json={"username": "longpw", "password": "!" + "x" * 128}).status_code == 422


def test_login_rejects_oversized_password():
    response = client.post("/login", data={"username": "testuser", "password": "x" * 129})
    assert response.status_code == 401
