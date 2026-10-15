# 🌱 Sprout

A houseplant care tracker built with React/Vite, FastAPI and PostgreSQL.
Docker Compose runs the app; Jenkins tests, analyses, scans and deploys it.
The pipeline follows the mentor's `../cicd-portal` reference, adapted to Python
and React. There are no GitHub Actions workflows.

```text
Browser -> localhost:8090 -> nginx (non-root :8080) -> FastAPI :8000 -> PostgreSQL
                                                         |
                                               Alembic schema migrations

Jenkins: checkout -> parallel unit tests -> SonarQube -> Quality Gate
        -> build -> security / SBOM -> release-image integration tests
        -> optional push -> backup / migrate / deploy / smoke
                                      failure -> verified application rollback
```

## Start locally

```sh
docker compose up -d --build --wait --wait-timeout 180
# App: http://localhost:8090
# API: http://localhost:8090/api/docs
docker compose stop
```

Local defaults are for development. Containers start on demand and published
ports bind to localhost. Data survives `stop` and `down`; `down -v` deletes it.
The first migration preserves a matching database created by the original app.
The API does not create or modify the schema at startup.

For hot reload:

```sh
# Backend: Python 3.12+; SQLite unless DATABASE_URL is explicitly configured.
cd backend
python -m venv .venv
# Activate the venv: .venv/Scripts/activate (Windows) or .venv/bin/activate (Unix).
pip install --require-hashes -r requirements-dev.txt
alembic upgrade head
uvicorn app.main:app --reload

# In another terminal: Node 24.15+ (24.x).
cd frontend
npm ci
npm run dev
```

## Verify changes

```sh
# From backend/:
pytest -q
pip-audit --strict

# From frontend/:
npm run test:ci
npm run build
npm audit --audit-level=moderate

# From the root, using the same real PostgreSQL engine as CI:
docker compose -p sprout-test -f docker-compose.test.yml run --build --rm backend-tests
docker compose -p sprout-test -f docker-compose.test.yml run --build --rm frontend-tests
docker compose -p sprout-test -f docker-compose.test.yml down -v
```

## Jenkins deployment

Use the mentor's existing portal or the optional reproducible stack in `ci/`.
Configure the `SonarQube` server, `sonar-token` analysis credential,
`registry-credentials` registry login, `sprout-db-password` database credential,
and the SonarQube webhook. For an existing Jenkins server configure a scanner
tool named `sonar-scanner`; the bundled CI image supplies its own scanner.

The [deployment runbook](docs/DEPLOYMENT.md) contains exact portal setup steps,
the credential mapping, initial legacy upgrade procedure, production commands,
backup/restore drills and rollback recovery. Run the separate
[`ci/selftest.Jenkinsfile`](ci/selftest.Jenkinsfile) job before the first release.

Pipeline parameters:

| Parameter | Default | Effect |
|---|---|---|
| `DEPLOY` | `true` | Release `main` only after every gate passes |
| `PUSH_IMAGE` | `false` | Publish the tested images using `registry-credentials` |
| `IMAGE_NAMESPACE` | empty | Docker Hub user/org; falls back to `DOCKERHUB_USER` or `local` |

Release tags contain the build number and Git revision. The same immutable image
IDs go through integration tests and deployment. Jenkins archives JUnit/coverage
reports, CycloneDX SBOMs and image metadata; database dumps remain private.
Automatic rollback restores both previous app images and checks their build and
health. It never silently downgrades the database schema.

## Project guide

| Path | Purpose |
|---|---|
| `backend/app`, `backend/tests` | API, configuration/readiness checks and regression tests |
| `backend/migrations` | Versioned schema, upgrade/downgrade and checked legacy adoption |
| `frontend/` | UI, tests, locked Node dependencies and non-root nginx image |
| `e2e/` | Tests through nginx -> API -> PostgreSQL using release images |
| `docker-compose.yml` | Local app with health checks, log/resource limits and an internal database network |
| `docker-compose.production.yml` | Production secrets and restart policy; requires explicit images |
| `docker-compose.test.yml`, `docker-compose.it.yml` | Disposable test environments |
| `scripts/` | Dependency locks, release, smoke, backup and safe empty-target restore |
| `ci/` | Optional pinned Jenkins/JCasC bootstrap and a portal self-test |

See [CONTRIBUTING.md](CONTRIBUTING.md) for review/quality requirements,
[docs/VERIFICATION.md](docs/VERIFICATION.md) for the validation record,
[cmd.md](cmd.md) for commands and [ROADMAP.md](ROADMAP.md) for product features.
Operational prerequisites such as HTTPS, access control, off-host backups,
monitoring and branch protection are described in the runbook; they require
configuration in the deployment environment.
