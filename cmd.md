# Sprout command cheat sheet

Run every command from the project root (`D:\CODE\CMC\Software-Deployment\sprout`).
They work in both PowerShell and Git Bash unless marked otherwise.

> Nothing starts automatically. Use the one-command scripts below, or the manual commands in sections 1–2.

---

## 0. One command for everything ⭐

| What | Command (from the project root) |
|---|---|
| **Start everything** (Docker Desktop if needed, Jenkins, SonarQube, app; waits until healthy; opens the browser) | `.\sprout.cmd` |
| Stop Jenkins, SonarQube and the app (data is kept) | `.\sprout.cmd stop` |
| Status | `.\sprout.cmd status` |

From Git Bash use `./sprout.cmd`. You can also double-click `sprout.cmd` in Explorer to start everything.

---

## 1. Jenkins + SonarQube (CI stack): http://localhost:8081 and http://localhost:9002

One compose file runs both (`jenkins`, `sonarqube`, `sonar-db`).

| What | Command |
|---|---|
| Start | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env up -d` |
| Stop (keeps jobs and history) | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env stop` |
| Status | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env ps` |
| Logs (one service) | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env logs -f jenkins` (or `sonarqube`) |
| Rebuild after editing `ci/jenkins/*` or `ci/.env` | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env up -d --build` |
| Show logins (Jenkins `admin` / `JENKINS_ADMIN_PASSWORD`, SonarQube `admin` / `SONAR_ADMIN_PASSWORD`) | PowerShell: `Get-Content ci/.env` / Bash: `cat ci/.env` |

- Job name: **sprout**. Open http://localhost:8081/job/sprout/ and click **Build Now** to build by hand.
- While Jenkins is running, it checks GitHub every 2 minutes and builds new commits on `main` automatically.
- Test results: build page → **Tests**. Code quality: http://localhost:9002/dashboard?id=sprout
- SonarQube takes 1–2 minutes to boot; the pipeline waits for it.

---

## 2. Deployed app: http://localhost:8090

| What | Command |
|---|---|
| Start the last release Jenkins deployed | `.\sprout.cmd` (it detects the image name and build) |
| Stop (keeps the database) | `docker compose stop` |
| Status | `docker compose ps` |
| Logs (all / one service) | `docker compose logs -f` / `docker compose logs -f backend` |
| Health check | `curl http://localhost:8090/api/health` |
| API docs (Swagger) | http://localhost:8090/api/docs |
| Build and run locally without Jenkins | `docker compose up -d --build` |
| ⚠️ Wipe the database (deletes all data) | `docker compose down -v` |

> Starting by hand instead of `sprout.cmd`: images are `<namespace>/sprout-*:<build>`, and the DB password is `SPROUT_DB_PASSWORD` from `ci/.env`.
> PowerShell: `$env:IMAGE_NAMESPACE="local"; $env:IMAGE_TAG="<build#>"; $env:POSTGRES_PASSWORD="<value>"; docker compose up -d --no-build`
> (`IMAGE_NAMESPACE` is your Docker Hub user once pushing is enabled)

---

## 3. Development (hot reload)

**Backend** (http://localhost:8000/api/docs). Uses a local SQLite file (`backend/sprout-dev.db`) unless `DATABASE_URL` is set.
```powershell
cd backend
python -m venv .venv            # first time only
.venv\Scripts\activate          # Git Bash: source .venv/Scripts/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload
```

**Frontend** (http://localhost:5173; proxies `/api` to :8000)
```bash
cd frontend
npm install                     # first time / after package.json changes
npm run dev
```

> Want Postgres in dev? `docker run -d --name sprout-dev-db -p 5432:5432 -e POSTGRES_USER=sprout -e POSTGRES_PASSWORD=sprout -e POSTGRES_DB=sprout postgres:16-alpine`,
> then before `uvicorn`: PowerShell `$env:DATABASE_URL="postgresql+psycopg://sprout:sprout@localhost:5432/sprout"`

---

## 4. Tests (run before pushing)

Quick (local):
```bash
cd backend
pytest -q                       # uses SQLite by default (activate .venv first)
cd ../frontend
npm test                        # npm run test:ci = with coverage
cd ..
```

Exactly like Jenkins (backend against real Postgres, in Docker):
```bash
docker compose -p sprout-test -f docker-compose.test.yml run --build --rm backend-tests
docker compose -p sprout-test -f docker-compose.test.yml run --build --rm frontend-tests
docker compose -p sprout-test -f docker-compose.test.yml down -v
```

End-to-end tests against your running app (⚠️ adds `e2e-…` plants to its database):
```bash
cd e2e
pip install -r requirements.txt
pytest -v                       # BASE_URL defaults to http://localhost:8090
```

---

## 5. Add a feature (see ROADMAP.md)

```bash
git switch main
git pull
git switch -c feat/<name>              # e.g. feat/care-log

# ...code + tests...

git add -A
git commit -m "Add <feature>"
git push -u origin feat/<name>         # optional: back up the branch / open a PR

# Deploy = merge into main and push. Jenkins builds it within ~2 min (if it's running)
git switch main
git merge feat/<name>
git push
```

Then follow the build at http://localhost:8081/job/sprout/ → the build number → **Console Output**.

---

## 6. Docker Hub (Push stage)

1. hub.docker.com → Account settings → **Personal access tokens** → New (Read & Write).
2. In `ci/.env`: `DOCKERHUB_USER=<your user>` and `DOCKERHUB_TOKEN=<token>`.
3. Restart the CI stack so Jenkins reloads its config: `.\sprout.cmd stop` then `.\sprout.cmd`.
4. The next build pushes `<user>/sprout-backend` and `<user>/sprout-frontend` (tags `<build#>` and `latest`).

Without a user, the Push stage is skipped and images stay local (`local/sprout-*`).

---

## 7. Troubleshooting

| Problem | Try |
|---|---|
| `failed to connect to the docker API` | Start Docker Desktop and wait until it says "Engine running" |
| Port 8081 / 9002 / 8090 already in use | Change `JENKINS_PORT` / `SONAR_PORT` in `ci/.env`, or `APP_PORT` (e.g. PowerShell: `$env:APP_PORT=8095`) |
| Build fails at **Unit tests** / **Integration test** | Build page → **Tests** shows which test failed; nothing was deployed |
| Build fails at **SonarQube** (Quality Gate) | Open http://localhost:9002/dashboard?id=sprout, fix the new issues or add tests for uncovered new code |
| SonarQube stage times out waiting | SonarQube is still booting or out of memory: `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env logs sonarqube` |
| Push fails (`unauthorized`) | Check `DOCKERHUB_USER` / `DOCKERHUB_TOKEN` in `ci/.env` (token needs Write), then restart the CI stack |
| Build fails at **Smoke test** | Jenkins rolls back to the previous version automatically; check `docker compose logs backend` |
| Backend can't log in to Postgres | The password in use differs from the one in the volume (see the note in section 2) |
| Clean up old images | `docker image prune -f` |
