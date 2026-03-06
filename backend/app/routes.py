from flask import Blueprint, jsonify, Response
from typing import Tuple

main_bp = Blueprint("main", __name__)


@main_bp.route("/api/health", methods=["GET"])
def health() -> Tuple[Response, int]:
    """Health check endpoint."""
    return jsonify({"status": "ok", "service": "backend"}), 200


@main_bp.route("/api/items", methods=["GET"])
def get_items() -> Tuple[Response, int]:
    """Returns a list of items from the database."""
    # Placeholder — replace with real DB queries via psycopg2
    items = [
        {"id": 1, "name": "Widget Alpha", "quantity": 42},
        {"id": 2, "name": "Widget Beta", "quantity": 17},
    ]
    return jsonify(items), 200
