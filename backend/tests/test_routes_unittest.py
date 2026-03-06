import unittest
from app import create_app


class TestRoutes(unittest.TestCase):
    def setUp(self) -> None:
        self.app = create_app()
        self.app.testing = True
        self.client = self.app.test_client()

    def test_health_returns_ok(self) -> None:
        response = self.client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data["status"], "ok")

    def test_health_service_name(self) -> None:
        response = self.client.get("/api/health")
        data = response.get_json()
        self.assertIn("service", data)

    def test_items_returns_list(self) -> None:
        response = self.client.get("/api/items")
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertIsInstance(data, list)

    def test_items_have_required_fields(self) -> None:
        response = self.client.get("/api/items")
        items = response.get_json()
        for item in items:
            self.assertIn("id", item)
            self.assertIn("name", item)
            self.assertIn("quantity", item)


if __name__ == "__main__":
    unittest.main()
