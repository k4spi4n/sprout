from pathlib import Path
from io import StringIO

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text

from app.database import Base


@pytest.fixture
def migration_db(tmp_path):
    engine = create_engine(f"sqlite:///{tmp_path / 'migration.db'}")
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    with engine.connect() as connection:
        config.attributes["connection"] = connection
        yield connection, config
    engine.dispose()


def test_fresh_schema_upgrade_downgrade_and_model_consistency(migration_db):
    connection, config = migration_db
    command.upgrade(config, "head")
    command.check(config)
    assert "plants" in inspect(connection).get_table_names()
    command.downgrade(config, "base")
    assert "plants" not in inspect(connection).get_table_names()
    command.upgrade(config, "head")


def test_adopts_original_schema_without_losing_data(migration_db):
    connection, config = migration_db
    Base.metadata.create_all(connection)
    connection.execute(text("INSERT INTO plants (name, water_every_days) VALUES ('Legacy fern', 7)"))
    command.upgrade(config, "head")
    assert connection.execute(text("SELECT name FROM plants")).scalar_one() == "Legacy fern"
    command.check(config)


def test_refuses_incompatible_legacy_schema(migration_db):
    connection, config = migration_db
    connection.execute(text("CREATE TABLE plants (id INTEGER PRIMARY KEY, name TEXT)"))
    with pytest.raises(RuntimeError, match="Legacy plants schema differs"):
        command.upgrade(config, "head")


def test_can_render_migration_sql_for_review(migration_db):
    _, config = migration_db
    config.output_buffer = StringIO()
    command.upgrade(config, "head", sql=True)
    assert "CREATE TABLE plants" in config.output_buffer.getvalue()


def test_refuses_legacy_schema_without_a_primary_key(migration_db):
    connection, config = migration_db
    connection.execute(text("""
        CREATE TABLE plants (
            id INTEGER NOT NULL, name VARCHAR(80) NOT NULL, species VARCHAR(120),
            location VARCHAR(80), water_every_days INTEGER NOT NULL, notes TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
        )
    """))
    with pytest.raises(RuntimeError, match="Legacy plants schema differs"):
        command.upgrade(config, "head")
