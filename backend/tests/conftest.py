import os

# Defaults to a local SQLite file so tests run without Postgres.
# CI (Jenkins) overrides DATABASE_URL to point at a throwaway Postgres container.
if os.getenv("DATABASE_URL") and os.getenv("SPROUT_TEST_DATABASE") != "1":
    raise RuntimeError(
        "Tests drop the schema. Use a disposable database and explicitly set SPROUT_TEST_DATABASE=1."
    )
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

import pytest  # noqa: E402
from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.database import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture
def client():
    Base.metadata.drop_all(engine)
    with engine.begin() as connection:
        connection.exec_driver_sql("DROP TABLE IF EXISTS alembic_version")
        config = Config("alembic.ini")
        config.attributes["connection"] = connection
        command.upgrade(config, "head")
    with TestClient(app) as c:
        yield c
    Base.metadata.drop_all(engine)
