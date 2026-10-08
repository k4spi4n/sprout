# Sprout roadmap

Sprout is a houseplant care tracker. You register your plants with a watering
schedule, log care (watering, fertilizing, …), and the app tells you which plants
are thirsty today.

The current code is a **base**: one working vertical slice (React → FastAPI → PostgreSQL)
plus a full CI/CD pipeline. Each item below is sized to fit in one small PR, so every
feature goes through Jenkins (test → build → deploy) on its own.

Legend: ✅ done · ⬜ planned

## v0.1: Base (done)
- ✅ `Plant` model: name, species, location, watering interval, notes
- ✅ `GET /api/plants`, `POST /api/plants`, `GET /api/health`
- ✅ React page: list plants and add a plant
- ✅ Docker images, docker-compose deployment, Jenkins pipeline with rollback

## v0.2: Manage plants
- ⬜ `GET /api/plants/{id}`, `PATCH /api/plants/{id}`, `DELETE /api/plants/{id}`
- ⬜ Edit and delete from the UI (plant detail panel)
- ⬜ Filter the list by location (`GET /api/plants?location=…`)

## v0.3: Care log (the core feature)
- ⬜ `CareEvent` model: `plant_id`, `kind` (`water` | `fertilize` | `mist` | `repot` | `prune`), `note`, `performed_at`
- ⬜ `POST /api/plants/{id}/care` and `GET /api/plants/{id}/care` (history)
- ⬜ "💧 Water now" button on each card
- ⬜ `DELETE /api/care/{id}` and an "Undo" toast after logging

## v0.4: Watering status
- ⬜ Compute `last_watered_at`, `next_water_due`, `days_left`, `status` (`overdue` | `due` | `ok`) on the API
  (single SQL query with `MAX(performed_at) FILTER (WHERE kind = 'water')`)
- ⬜ Sort plants by urgency; colored status badge plus a progress bar on cards
- ⬜ "Thirsty" / "Happy" filter tabs

## v0.5: Dashboard
- ⬜ `GET /api/stats`: plant count, overdue count, waterings in the last 7 days
- ⬜ Stats bar at the top of the page
- ⬜ "Water all due" bulk action

## v0.6: Hardening
- ⬜ Alembic migrations (replace `Base.metadata.create_all`)
- ⬜ Seasonal adjustment: water less often in winter (per-plant multiplier)
- ⬜ Plant photos (upload to a Docker volume)
- ⬜ Push images to a registry (Docker Hub / GHCR) from Jenkins and deploy by tag

## How to add a feature
1. Branch off `main`: `git switch -c feat/care-log`
2. Backend: model → schema → router → test in `backend/tests/`
3. Frontend: `api.js` → component → unit test (`*.test.js`)
4. Run locally (see README), then merge to `main` and push.
   Jenkins picks up the commit within ~2 minutes, runs the tests, and redeploys.
