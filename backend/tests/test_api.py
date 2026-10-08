def test_health(client):
    res = client.get("/api/health")
    assert res.status_code == 200
    assert res.json()["database"] == "ok"


def test_create_and_list_plants(client):
    res = client.post(
        "/api/plants",
        json={"name": "Monty", "species": "Monstera deliciosa", "location": "Living room", "water_every_days": 7},
    )
    assert res.status_code == 201
    plant = res.json()
    assert plant["id"] > 0
    assert plant["name"] == "Monty"

    res = client.get("/api/plants")
    assert res.status_code == 200
    assert [p["name"] for p in res.json()] == ["Monty"]


def test_rejects_invalid_watering_interval(client):
    res = client.post("/api/plants", json={"name": "Cactus", "water_every_days": 0})
    assert res.status_code == 422
