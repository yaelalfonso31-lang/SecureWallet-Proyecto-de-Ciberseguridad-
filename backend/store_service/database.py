from sqlalchemy.orm import DeclarativeBase

from shared.config import settings
from shared.database import make_session_factory


class Base(DeclarativeBase):
    pass


engine, SessionLocal = make_session_factory(settings.store_database_url)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
