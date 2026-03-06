"""
tests/test_integration.py
Integration test suite — requires a real running database.

These tests are only executed during staging (Phase 2B) when
DATABASE_URL is present in the environment. They are completely
skipped during local unit test runs.

Add your integration tests here as the project grows.
"""
import os
import unittest


# Guard: skip the entire module if DATABASE_URL is not set
DB_URL = os.environ.get("DATABASE_URL", "")
SKIP_REASON = "DATABASE_URL not set — integration tests require a live database"


@unittest.skipUnless(DB_URL, SKIP_REASON)
class TestDatabaseIntegration(unittest.TestCase):
    """Integration tests that verify real database connectivity."""

    def test_database_connection(self) -> None:
        """Verify that a connection to PostgreSQL can be established."""
        import psycopg2  # noqa: import-outside-toplevel

        try:
            conn = psycopg2.connect(DB_URL)
            conn.close()
        except psycopg2.OperationalError as exc:
            self.fail(f"Could not connect to database: {exc}")

    def test_items_table_exists(self) -> None:
        """Verify that the items table exists and is queryable."""
        import psycopg2  # noqa: import-outside-toplevel

        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()
        cur.execute(
            "SELECT EXISTS (SELECT FROM information_schema.tables "
            "WHERE table_name = 'items');"
        )
        exists = cur.fetchone()[0]  # type: ignore[index]
        cur.close()
        conn.close()
        self.assertTrue(exists, "Table 'items' should exist in the database")


@unittest.skipUnless(DB_URL, SKIP_REASON)
class TestAPIIntegration(unittest.TestCase):
    """Integration tests that exercise the full API stack."""

    def setUp(self) -> None:
        """Set up Flask test client with real DB injected via env."""
        from app import create_app  # noqa: import-outside-toplevel

        self.app = create_app()
        self.app.testing = True
        self.client = self.app.test_client()

    def test_health_endpoint_with_db(self) -> None:
        """Health endpoint should return OK even with real DB configured."""
        response = self.client.get("/api/health")
        self.assertEqual(response.status_code, 200)

    def test_items_endpoint_returns_data(self) -> None:
        """Items endpoint should return data from the real database."""
        response = self.client.get("/api/items")
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertIsInstance(data, list)


if __name__ == "__main__":
    unittest.main()
