"""
Data models / DB interaction layer.
Replace with SQLAlchemy models or a psycopg2 helper class as needed.
"""
from dataclasses import dataclass


@dataclass
class Item:
    id: int
    name: str
    quantity: int
