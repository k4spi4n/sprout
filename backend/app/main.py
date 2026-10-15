import logging
import os
import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from . import models  # noqa: F401  (registers tables on Base.metadata)
from .database import Base, engine, get_db
from .routers import plants

log = logging.getLogger("sprout")


def init_db(retries: int = 10, delay: float = 2.0) -> None:
    """Create tables, waiting for Postgres to accept connections.

    Roadmap: replace create_all with Alembic migrations once the schema starts changing.
    """
    for attempt in range(1, retries + 1):
        try:
            Base.metadata.create_all(engine)
            return
        except OperationalError:
            if attempt == retries:
                raise
            log.warning("Database not ready (attempt %s/%s), retrying...", attempt, retries)
            time.sleep(delay)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(
    title="Sprout API",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
)
app.include_router(plants.router)


@app.get("/api/health", tags=["meta"])
def health(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    # APP_BUILD is the Jenkins build number baked into the deployment; the smoke test checks it.
    return {
        "status": "ok",
        "database": "ok",
        "version": app.version,
        "build": os.getenv("APP_BUILD", "dev"),
    }
