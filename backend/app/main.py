import logging
import os
from pathlib import Path

from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from fastapi import FastAPI, HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from . import models  # noqa: F401  (registers tables on Base.metadata)
from .database import DbSession
from .routers import plants

log = logging.getLogger("sprout")


config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
schema_heads = set(ScriptDirectory.from_config(config).get_heads())


app = FastAPI(
    title="Sprout API",
    version="0.1.0",
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
)
app.include_router(plants.router)


@app.get("/api/live", tags=["meta"])
def live():
    """Process liveness, deliberately independent of database availability."""
    return {"status": "ok"}


@app.get("/api/health", tags=["meta"])
def health(db: DbSession):
    try:
        db.execute(text("SELECT 1"))
        current_heads = set(MigrationContext.configure(db.connection()).get_current_heads())
        if current_heads != schema_heads:
            raise HTTPException(status_code=503, detail="Database migrations are required")
    except SQLAlchemyError:
        log.warning("Database readiness check failed")
        raise HTTPException(status_code=503, detail="Database unavailable") from None
    # APP_BUILD is the Jenkins build number baked into the deployment; the smoke test checks it.
    return {
        "status": "ok",
        "database": "ok",
        "version": app.version,
        "build": os.getenv("APP_BUILD", "dev"),
        "revision": os.getenv("APP_REVISION", "unknown"),
    }
