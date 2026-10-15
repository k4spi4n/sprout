# 🌱 Sprout

A small houseplant care tracker built with **React (Vite)**, **FastAPI**, and **PostgreSQL**.
It is deployed with **Docker Compose**. CI/CD runs on **Jenkins in Docker**, with code quality checked
by **SonarQube** and images pushed to **Docker Hub** (no GitHub Actions).

This repo is a **base app** that new features are added to step by step. See [ROADMAP.md](ROADMAP.md).
For day-to-day commands, see [cmd.md](cmd.md).

## Architecture

```
                 ┌──────────── docker compose (project "sprout") ─────────────┐
 browser ──:8090─┤ frontend (nginx)  ──/api──▶  backend (FastAPI)  ──▶  db     │
                 │  React static build          uvicorn :8000         Postgres │
                 └────────────────────────────────────────────────────────────┘

 ┌──────────── ci/docker-compose.jenkins.yml (project "sprout-jenkins") ────────────┐
 │ Jenkins :8081 ──▶ SonarQube :9002 (+ Postgres)                                    │
 │    │  polls GitHub main every 2 min                                               │
 │    └─ /var/run/docker.sock ──▶ host Docker (builds, tests, deploys) ──▶ Docker Hub │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

| Path | What |
|---|---|
| `backend/` | FastAPI app (`app/`), pytest tests (`tests/`), multi-stage Dockerfile (`test` / `runtime`) |
| `frontend/` | React + Vite, Vitest + Testing Library tests, nginx config, multi-stage Dockerfile (`test` / `build` / `runtime`) |
| `e2e/` | End-to-end API/UI-serving tests, run against the full stack |
| `docker-compose.yml` | Deployment stack: db + backend + frontend (images `<namespace>/sprout-*:<build>`) |
| `docker-compose.test.yml` | Unit-test stack: backend tests + throwaway Postgres, frontend tests |
| `docker-compose.it.yml` | Integration-test override: isolated stack (no published ports) + `e2e` runner |
| `scripts/smoke-test.sh` | Read-only post-deploy checks |
| `sonar-project.properties` | SonarQube analysis settings (sources, tests, coverage reports, quality gate) |
| `Jenkinsfile` | The CI/CD pipeline (below) |
| `ci/` | Jenkins (Docker CLI + SonarScanner, Configuration as Code) and SonarQube |
| `sprout.cmd` / `sprout.ps1` | One command to start/stop everything |

## Run locally

### Option A: everything in Docker
```bash
docker compose up --build
# App:      http://localhost:8090
# API docs: http://localhost:8090/api/docs
```

### Option B: dev mode with hot reload
```bash
# 1) Backend: http://localhost:8000/api/docs
#    Uses a local SQLite file by default. For Postgres, set DATABASE_URL=postgresql+psycopg://user:pass@localhost:5432/db
cd backend
python -m venv .venv && source .venv/Scripts/activate   # Linux/macOS: .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload

# 2) Frontend: http://localhost:5173 (proxies /api to :8000)
cd frontend
npm install
npm run dev
```

### Tests
```bash
cd backend  && pytest -q        # SQLite by default; set DATABASE_URL to run against Postgres
cd frontend && npm test         # npm run test:ci also writes coverage + JUnit to frontend/reports

# Same as Jenkins (backend against real Postgres):
docker compose -p sprout-test -f docker-compose.test.yml run --build --rm backend-tests
docker compose -p sprout-test -f docker-compose.test.yml run --build --rm frontend-tests
docker compose -p sprout-test -f docker-compose.test.yml down -v
```

## CI/CD with Jenkins + SonarQube (in Docker)

1. Configure:
   ```bash
   cp ci/.env.example ci/.env     # repo URL, passwords, Docker Hub user + token, DOCKER_GID
   ```
2. Start everything: `.\sprout.cmd`
   (or `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env up -d --build`)
3. Open http://localhost:8081 and log in with `JENKINS_ADMIN_ID` / `JENKINS_ADMIN_PASSWORD`.
   The **sprout** job already exists (created by `ci/jenkins/casc.yaml`). Click **Build Now** for the first run.
   After that, Jenkins polls GitHub every 2 minutes and builds every new commit on `main`.
4. SonarQube is at http://localhost:9002 (user `admin`, password `SONAR_ADMIN_PASSWORD`).
   The first pipeline run replaces SonarQube's default `admin/admin` password with that one.

### Pipeline stages

```
Checkout → Unit tests → SonarQube → Build → Integration test → Push → Deploy → Smoke test
             (parallel)  quality gate  compose   isolated stack    Docker Hub          └─ fail → rollback
```

| Stage | What happens | Fails when |
|---|---|---|
| Checkout | Clone `main` from GitHub | |
| Unit tests | `docker-compose.test.yml`: **backend** pytest against a throwaway **PostgreSQL**, **frontend** Vitest + Testing Library. JUnit results are shown in Jenkins; coverage goes to SonarQube | any test fails |
| SonarQube | `sonar-scanner` with a short-lived per-build token. Bugs, vulnerabilities, code smells, duplication and coverage are checked against the **Quality Gate** | Quality Gate is red |
| Build | `docker compose build`, giving `<namespace>/sprout-backend:<build#>` and `.../sprout-frontend:<build#>` (+ `latest`). The build number is baked into the backend image | build error |
| Integration test | Starts the **release images** in an isolated compose project (own network and DB, no ports) and runs `e2e/` through nginx → FastAPI → Postgres | any e2e test fails |
| Push | `docker compose push` to Docker Hub (`<build#>` and `latest`). Skipped if `DOCKERHUB_USER` is empty | push error |
| Deploy | `docker compose up -d --no-build --wait` with the DB password from Jenkins credentials | containers unhealthy |
| Smoke test | Read-only checks on the live app: health + DB, **build N is really live**, index.html, JS bundle, API, docs | any check fails |
| Rollback | If Deploy or Smoke test fails, the previously running release is started again | |

### Docker Hub
1. Create an access token: hub.docker.com → Account settings → Personal access tokens (Read & Write).
2. Put `DOCKERHUB_USER` and `DOCKERHUB_TOKEN` in `ci/.env`, then restart Jenkins: `.\sprout.cmd stop` then `.\sprout.cmd`.
   Jenkins reads them at startup, through Configuration as Code.
3. The next build pushes `docker.io/<user>/sprout-backend` and `docker.io/<user>/sprout-frontend`.

### Notes
- **On-demand:** nothing restarts automatically when Docker starts (`restart: "no"`). Use `.\sprout.cmd` / `.\sprout.cmd stop`.
  Jenkins polls GitHub only while it's running.
- **Why polling and not webhooks?** Jenkins runs on localhost, so GitHub can't reach it. To use a webhook,
  expose Jenkins (for example with `ngrok http 8081`), add a GitHub webhook to `<url>/github-webhook/`,
  and install the `github` plugin.
- **Docker socket:** Jenkins controls the host Docker daemon ("Docker outside of Docker"). On Linux,
  set `DOCKER_GID` to the host's `docker` group id.
- **Resources:** SonarQube needs about 2 GB RAM. Stop the CI stack when you're not using it.
- **DB password:** Postgres only reads `POSTGRES_PASSWORD` when it first creates the `pgdata` volume.
  To change it later, remove the volume (this deletes the data) or run `ALTER USER` in the database.
- **Private repo?** Add a GitHub token credential in `casc.yaml` and use `credentials('<id>')` in the job's `remote {}` block.
