"""End-to-end tests against a running Sprout stack (nginx -> FastAPI -> PostgreSQL).

Run by Jenkins against a throwaway stack built from the release images (docker-compose.it.yml).
Locally: BASE_URL=http://localhost:8090 pytest e2e   (this creates plants in that database!)
"""

import os
import re
import time
import uuid

import httpx
import pytest

BASE_URL = os.getenv("BASE_URL", "http://localhost:8090")
EXPECTED_BUILD = os.getenv("EXPECTED_BUILD")


@pytest.fixture(scope="session")
def http():
    with httpx.Client(base_url=BASE_URL, timeout=10) as client:
        deadline = time.monotonic() + 60
        while True:
            try:
                if client.get("/api/health").status_code == 200:
                    break
            except httpx.TransportError:
                pass
            if time.monotonic() > deadline:
                pytest.fail(f"{BASE_URL} did not become healthy within 60s")
            time.sleep(1)
        yield client


def test_health_reports_database_and_expected_build(http):
    body = http.get("/api/health").json()
    assert body["status"] == "ok"
    assert body["database"] == "ok"
    if EXPECTED_BUILD:
        assert body["build"] == EXPECTED_BUILD


def test_frontend_and_its_assets_are_served(http):
    res = http.get("/")
    assert res.status_code == 200
    assert 'id="root"' in res.text

    assets = re.findall(r'(?:src|href)="(/assets/[^"]+)"', res.text)
    assert assets, "index.html references no built assets"
    for asset in assets:
        assert http.get(asset).status_code == 200, asset


def test_client_side_routes_fall_back_to_index(http):
    res = http.get("/plants/some-client-route")
    assert res.status_code == 200
    assert 'id="root"' in res.text


def test_plant_round_trip_through_proxy_and_database(http):
    name = f"e2e-{uuid.uuid4().hex[:8]}"
    res = http.post("/api/plants", json={"name": name, "location": "CI", "water_every_days": 5})
    assert res.status_code == 201
    created = res.json()

    listed = {p["id"]: p for p in http.get("/api/plants").json()}
    assert created["id"] in listed
    assert listed[created["id"]]["name"] == name
    assert listed[created["id"]]["water_every_days"] == 5


def test_validation_errors_pass_through_the_proxy(http):
    res = http.post("/api/plants", json={"name": "Cactus", "water_every_days": 0})
    assert res.status_code == 422


def test_api_docs_are_reachable(http):
    assert http.get("/api/docs").status_code == 200
    assert http.get("/api/openapi.json").json()["info"]["title"] == "Sprout API"
