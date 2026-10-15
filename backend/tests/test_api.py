def make_plant(client, **overrides):
    payload = {"name": "Monty", "species": "Monstera deliciosa", "location": "Living room", "water_every_days": 7}
    payload.update(overrides)
    res = client.post("/api/plants", json=payload)
    assert res.status_code == 201, res.text
    return res.json()


def test_health_reports_database_and_build(client):
    res = client.get("/api/health")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "ok"
    assert body["database"] == "ok"
    assert body["build"] == "dev"


def test_list_is_empty_initially(client):
    res = client.get("/api/plants")
    assert res.status_code == 200
    assert res.json() == []


def test_create_returns_full_plant(client):
    plant = make_plant(client, notes="Likes bright, indirect light")
    assert plant["id"] > 0
    assert plant["name"] == "Monty"
    assert plant["species"] == "Monstera deliciosa"
    assert plant["water_every_days"] == 7
    assert plant["notes"] == "Likes bright, indirect light"
    assert plant["created_at"]


def test_optional_fields_default_to_null(client):
    plant = make_plant(client, species=None, location=None)
    assert plant["species"] is None
    assert plant["location"] is None
    assert plant["notes"] is None


def test_created_plants_are_persisted_newest_first(client):
    first = make_plant(client, name="Fern")
    second = make_plant(client, name="Cactus", water_every_days=21)

    names = [p["name"] for p in client.get("/api/plants").json()]
    assert names == [second["name"], first["name"]]


def test_rejects_invalid_watering_interval(client):
    for bad in (0, 61, -3):
        res = client.post("/api/plants", json={"name": "Cactus", "water_every_days": bad})
        assert res.status_code == 422, bad


def test_rejects_missing_or_blank_name(client):
    assert client.post("/api/plants", json={"water_every_days": 7}).status_code == 422
    assert client.post("/api/plants", json={"name": "", "water_every_days": 7}).status_code == 422


def test_rejects_too_long_name(client):
    res = client.post("/api/plants", json={"name": "x" * 81, "water_every_days": 7})
    assert res.status_code == 422


def test_openapi_docs_are_served_under_api_prefix(client):
    assert client.get("/api/openapi.json").status_code == 200
    assert client.get("/api/docs").status_code == 200


def test_readiness_refuses_unmigrated_database_but_process_is_live(client):
    from sqlalchemy import text
    from app.database import engine

    with engine.begin() as connection:
        connection.execute(text("DELETE FROM alembic_version"))
    assert client.get("/api/health").status_code == 503
    assert client.get("/api/live").status_code == 200


def test_readiness_database_failure_returns_safe_503(client):
    from sqlalchemy.exc import OperationalError
    from app.database import get_db
    from app.main import app

    class UnavailableDatabase:
        def execute(self, statement):
            raise OperationalError("sensitive connection details", {}, Exception("down"))

    app.dependency_overrides[get_db] = lambda: UnavailableDatabase()
    try:
        response = client.get("/api/health")
        assert response.status_code == 503
        assert response.json() == {"detail": "Database unavailable"}
        assert client.get("/api/live").status_code == 200
    finally:
        app.dependency_overrides.clear()


def test_adopts_real_database_schema_and_preserves_existing_plants(client):
    from alembic import command
    from alembic.config import Config
    from sqlalchemy import text
    from app.database import engine

    make_plant(client, name="Existing production fern")
    with engine.begin() as connection:
        connection.exec_driver_sql("DROP TABLE alembic_version")
        config = Config("alembic.ini")
        config.attributes["connection"] = connection
        command.upgrade(config, "head")
        command.check(config)
        assert connection.execute(text("SELECT name FROM plants")).scalar_one() == "Existing production fern"
    assert client.get("/api/health").status_code == 200
