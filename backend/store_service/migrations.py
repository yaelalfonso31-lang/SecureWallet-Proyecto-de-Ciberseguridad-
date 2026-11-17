"""Migración ligera para bases de datos que ya existían.

`Base.metadata.create_all` crea tablas nuevas pero NO agrega columnas a tablas existentes.
Esta función agrega `products.category` si falta, así nadie tiene que borrar su `store.db`.
Cuando el esquema se estabilice conviene pasar a Alembic.
"""
from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine

# Categoría de los productos de ejemplo (solo se usa al migrar una BD existente).
KNOWN_CATEGORIES = {
    "Audífonos Bluetooth": "Audio",
    "Teclado mecánico": "Computación",
    "Mochila para laptop": "Accesorios",
    "Cargador USB-C 65W": "Computación",
    "Libro: Criptografía aplicada": "Libros",
}


def ensure_schema(engine: Engine) -> None:
    inspector = inspect(engine)
    if "products" not in inspector.get_table_names():
        return
    columns = {c["name"] for c in inspector.get_columns("products")}
    if "category" in columns:
        return
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE products ADD COLUMN category VARCHAR(40) NOT NULL DEFAULT 'General'"))
        for name, category in KNOWN_CATEGORIES.items():
            conn.execute(
                text("UPDATE products SET category = :category WHERE name = :name"),
                {"category": category, "name": name},
            )
