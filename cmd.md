# Sprout command cheat sheet

Run from the repository root unless noted. Full setup and recovery instructions:
[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

| Action | Command |
|---|---|
| Build/start the local app and apply migrations | `docker compose up -d --build --wait --wait-timeout 180` |
| Stop app; keep data | `docker compose stop` |
| App status | `docker compose ps -a` |
| Follow app logs | `docker compose logs -f backend frontend` |
| Readiness, including database/schema | `curl http://localhost:8090/api/health` |
| Process liveness | `curl http://localhost:8090/api/live` |
| API docs | `http://localhost:8090/api/docs` |
| Start bundled CI | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env up -d --build` |
| Stop bundled CI | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env stop` |
| Windows convenience launcher | `.\sprout.cmd` / `.\sprout.cmd stop` / `.\sprout.cmd status` |

Copy `ci/.env.example` to `ci/.env` before starting bundled CI. Configure the
SonarQube analysis user/token and webhook through the portal. Jenkins is at
`http://localhost:8081`, SonarQube at `http://localhost:9002`.

The convenience launcher starts existing managed containers without changing
their image references, secrets or schema. A legacy installation is rebuilt once
for the migration transition; back up existing data first. Production deployment
goes through Jenkins or `scripts/deploy.sh`, as described in the runbook.

```sh
# Backend tests against disposable PostgreSQL:
docker compose -p sprout-test -f docker-compose.test.yml run --build --rm backend-tests
docker compose -p sprout-test -f docker-compose.test.yml down -v

# Frontend tests:
docker compose -p sprout-test -f docker-compose.test.yml run --build --rm frontend-tests
docker compose -p sprout-test -f docker-compose.test.yml down -v

# From backend/ (activated virtual environment):
pytest -q
alembic upgrade head
alembic check
pip-audit --strict

# From frontend/ (Node 24.x):
npm ci
npm run test:ci
npm run build
npm audit --audit-level=moderate

# From root, uv 0.13.1 installed:
sh scripts/lock-dependencies.sh

# From a Linux deployment agent with the correct project/Compose environment:
sh scripts/backup-db.sh .backups/manual.dump
sh scripts/deploy.sh rollback
```

`docker compose down -v` permanently deletes the selected project's database.
Use it only for disposable test projects or an intentional data reset.
