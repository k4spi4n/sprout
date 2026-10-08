# 🌱 Sprout

A small houseplant care tracker built with **React (Vite)**, **FastAPI**, and **PostgreSQL**.
It is deployed with **Docker Compose**, and CI/CD runs on **Jenkins in Docker** (no GitHub Actions).

This repo is a **base app** that new features are added to step by step. See [ROADMAP.md](ROADMAP.md).

## Architecture

```
                 ┌──────────── docker compose (project "sprout") ─────────────┐
 browser ──:8090─┤ frontend (nginx)  ──/api──▶  backend (FastAPI)  ──▶  db     │
                 │  React static build          uvicorn :8000         Postgres │
                 └────────────────────────────────────────────────────────────┘

 GitHub (main) ◀── poll every 2 min ── Jenkins (Docker, :8081) ── /var/run/docker.sock ──▶ host Docker
```

| Path | What |
|---|---|
| `backend/` | FastAPI app (`app/`), pytest tests (`tests/`), multi-stage Dockerfile (`test` / `runtime`) |
| `frontend/` | React + Vite, Vitest tests, nginx config, multi-stage Dockerfile (`test` / `build` / `runtime`) |
| `docker-compose.yml` | Deployment stack: db + backend + frontend |
| `Jenkinsfile` | Pipeline: checkout → tests → build images → deploy → smoke test (with rollback) |
| `ci/` | Dockerized Jenkins: image with Docker CLI, plugins, Configuration as Code (admin user, credentials, job) |

## Run locally

### Option A: everything in Docker
```bash
docker compose up --build
# App:      http://localhost:8090
# API docs: http://localhost:8090/api/docs
```

### Option B: dev mode with hot reload
```bash
# 1) Postgres for dev (matches the backend's default DATABASE_URL)
docker run -d --name sprout-dev-db -p 5432:5432   -e POSTGRES_USER=sprout -e POSTGRES_PASSWORD=sprout -e POSTGRES_DB=sprout postgres:16-alpine

# 2) Backend: http://localhost:8000/api/docs
cd backend
python -m venv .venv && source .venv/Scripts/activate   # Linux/macOS: .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload

# 3) Frontend: http://localhost:5173 (proxies /api to :8000)
cd frontend
npm install
npm run dev
```

### Tests
```bash
cd backend  && pytest -q        # SQLite by default; set DATABASE_URL to run against Postgres
cd frontend && npm test
```

## CI/CD with Jenkins (in Docker)

1. Configure:
   ```bash
   cp ci/.env.example ci/.env     # set SPROUT_REPO_URL, passwords, DOCKER_GID
   ```
2. Start Jenkins:
   ```bash
   docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env up -d --build
   ```
3. Open http://localhost:8081 and log in with `JENKINS_ADMIN_ID` / `JENKINS_ADMIN_PASSWORD`.
   The **sprout** job already exists (created by `ci/jenkins/casc.yaml`). Click **Build Now** for the first run.
   After that, Jenkins polls GitHub every 2 minutes and builds every new commit on `main`.

### Pipeline stages

| Stage | What happens |
|---|---|
| Checkout | Clone `main` from GitHub |
| Test (parallel) | **Backend:** build the `test` image, start a throwaway Postgres on a private network, run `pytest`. **Frontend:** build the `test` image (`npm test` runs inside it) |
| Build images | `sprout-backend:<build#>` and `sprout-frontend:<build#>` (also tagged `latest`) |
| Deploy | `IMAGE_TAG=<build#> docker compose up -d --no-build` with the DB password from Jenkins credentials |
| Smoke test | `curl http://frontend/api/health` from inside the app network (nginx → FastAPI → Postgres) |
| Rollback | If deploy or smoke test fails, redeploy the image tag that was running before |

### Notes
- **Why polling and not webhooks?** Jenkins runs on localhost, so GitHub can't reach it. To use a webhook,
  expose Jenkins (for example with `ngrok http 8081`), add a GitHub webhook to `<url>/github-webhook/`,
  and install the `github` plugin.
- **Docker socket:** Jenkins controls the host Docker daemon ("Docker outside of Docker"). On Linux,
  set `DOCKER_GID` to the host's `docker` group id.
- **DB password:** Postgres only reads `POSTGRES_PASSWORD` when it first creates the `pgdata` volume.
  To change it later, remove the volume (this deletes the data) or run `ALTER USER` in the database.
- **Private repo?** Add a GitHub token credential in `casc.yaml` and use `credentials('<id>')` in the job's `remote {}` block.
