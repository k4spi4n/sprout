import pytest

from app.database import database_url


@pytest.fixture(autouse=True)
def clean_database_environment(monkeypatch):
    for key in ("DATABASE_URL", "POSTGRES_HOST", "POSTGRES_PASSWORD", "POSTGRES_PASSWORD_FILE", "SPROUT_ENV"):
        monkeypatch.delenv(key, raising=False)


def test_password_punctuation_is_not_parsed_as_a_url(monkeypatch, tmp_path):
    password = "strong:@/?#% & password with punctuation"
    secret = tmp_path / "password"
    secret.write_text(password + "\n")
    monkeypatch.setenv("SPROUT_ENV", "production")
    monkeypatch.setenv("POSTGRES_HOST", "db")
    monkeypatch.setenv("POSTGRES_PASSWORD_FILE", str(secret))
    url = database_url()
    assert url.password == password
    assert url.host == "db"


def test_production_refuses_implicit_sqlite_or_explicit_url(monkeypatch):
    monkeypatch.setenv("SPROUT_ENV", "production")
    with pytest.raises(ValueError, match="explicitly configured"):
        database_url()
    monkeypatch.setenv("DATABASE_URL", "sqlite:///test.db")
    with pytest.raises(ValueError, match="Production uses"):
        database_url()


def test_production_refuses_development_password(monkeypatch, tmp_path):
    secret = tmp_path / "password"
    secret.write_text("sprout")
    monkeypatch.setenv("SPROUT_ENV", "production")
    monkeypatch.setenv("POSTGRES_HOST", "db")
    monkeypatch.setenv("POSTGRES_PASSWORD_FILE", str(secret))
    with pytest.raises(ValueError, match="unique password"):
        database_url()
