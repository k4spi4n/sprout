import os

# Defaults to a local SQLite file so tests run without Postgres.
# CI (Jenkins) overrides DATABASE_URL to point at a throwaway Postgres container.
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.database import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture()
def client():
    Base.metadata.drop_all(engine)
    with TestClient(app) as c:  # runs lifespan -> create_all
        yield c
    Base.metadata.drop_all(engine)
