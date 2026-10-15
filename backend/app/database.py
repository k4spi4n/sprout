import os
from pathlib import Path
from typing import Annotated

from fastapi import Depends
from sqlalchemy import URL, create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

def database_url():
    explicit_url = os.getenv("DATABASE_URL")
    production = os.getenv("SPROUT_ENV") == "production"
    if explicit_url:
        if production:
            raise ValueError("Production uses POSTGRES_* settings and POSTGRES_PASSWORD_FILE")
        return explicit_url
    if os.getenv("POSTGRES_HOST"):
        password_file = os.getenv("POSTGRES_PASSWORD_FILE")
        password = (Path(password_file).read_text().rstrip("\r\n") if password_file
                    else os.getenv("POSTGRES_PASSWORD", ""))
        if production and (not password_file or len(password) < 20 or password.lower().startswith("change-me")):
            raise ValueError("Production requires a password file with a unique password of at least 20 characters")
        # URL.create safely handles punctuation in passwords without URL encoding by callers.
        return URL.create(
            "postgresql+psycopg", username=os.getenv("POSTGRES_USER", "sprout"),
            password=password, host=os.environ["POSTGRES_HOST"], port=5432,
            database=os.getenv("POSTGRES_DB", "sprout"), query={"connect_timeout": "5"},
        )
    if production:
        raise ValueError("Production requires an explicitly configured PostgreSQL database")
    return "sqlite:///./sprout-dev.db"


DATABASE_URL = database_url()

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


DbSession = Annotated[Session, Depends(get_db)]
