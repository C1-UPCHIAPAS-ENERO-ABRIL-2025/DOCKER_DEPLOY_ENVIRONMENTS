import pytest
from app import create_app


@pytest.fixture
def client():
    app = create_app()
    app.testing = True
    with app.test_client() as client:
        yield client


def test_health_returns_ok(client) -> None:
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "ok"


def test_health_service_name(client) -> None:
    response = client.get("/api/health")
    data = response.get_json()
    assert "service" in data


def test_items_returns_list(client) -> None:
    response = client.get("/api/items")
    assert response.status_code == 200
    data = response.get_json()
    assert isinstance(data, list)


def test_items_have_required_fields(client) -> None:
    response = client.get("/api/items")
    items = response.get_json()
    for item in items:
        assert "id" in item
        assert "name" in item
        assert "quantity" in item
