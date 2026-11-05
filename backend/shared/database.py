from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker


def make_session_factory(url: str):
    """Crea (engine, SessionLocal) para una URL de base de datos."""
    kwargs = {}
    if url.startswith("sqlite"):
        kwargs["connect_args"] = {"check_same_thread": False}
    engine = create_engine(url, **kwargs)
    session_local = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    return engine, session_local
