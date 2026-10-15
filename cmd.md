# Sprout command cheat sheet

Run every command from the project root (`D:\CODE\CMC\Software-Deployment\sprout`).
They work in both PowerShell and Git Bash unless marked otherwise.

> Nothing starts automatically. Use the one-command scripts below, or the manual commands in sections 1–2.

---

## 0. One command for everything ⭐

| What | Command (from the project root) |
|---|---|
| **Start everything** (Docker Desktop if needed, Jenkins, app; waits until healthy; opens the browser) | `.\sprout.cmd` |
| Stop Jenkins and the app (data is kept) | `.\sprout.cmd stop` |
| Status | `.\sprout.cmd status` |

From Git Bash use `./sprout.cmd`. You can also double-click `sprout.cmd` in Explorer to start everything.

---

## 1. Jenkins (CI/CD server): http://localhost:8081

| What | Command |
|---|---|
| Start | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env up -d` |
| Stop (keeps jobs and history) | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env stop` |
| Status | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env ps` |
| Logs | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env logs -f` |
| Rebuild after editing `ci/jenkins/*` (plugins, casc.yaml) | `docker compose -f ci/docker-compose.jenkins.yml --env-file ci/.env up -d --build` |
| Show login (user `admin`) | PowerShell: `Get-Content ci/.env` / Bash: `cat ci/.env` |

- Job name: **sprout**. Open http://localhost:8081/job/sprout/ and click **Build Now** to build by hand.
- While Jenkins is running, it checks GitHub every 2 minutes and builds new commits on `main` automatically.

---

## 2. Deployed app: http://localhost:8090

| What | Command |
|---|---|
| Start (last image Jenkins built) | `docker compose up -d --no-build` |
| Stop (keeps the database) | `docker compose stop` |
| Status | `docker compose ps` |
| Logs (all / one service) | `docker compose logs -f` / `docker compose logs -f backend` |
| Health check | `curl http://localhost:8090/api/health` |
| API docs (Swagger) | http://localhost:8090/api/docs |
| Build and run locally without Jenkins | `docker compose up -d --build` |
| ⚠️ Wipe the database (deletes all data) | `docker compose down -v` |

> If Jenkins deployed the app first, the database password is `SPROUT_DB_PASSWORD` from `ci/.env`.
> To start the app by hand with that database, set it first:
> PowerShell: `$env:POSTGRES_PASSWORD="<value>"; docker compose up -d --no-build`

---

## 3. Development (hot reload)

```bash
# Postgres for dev (one time; later just: docker start sprout-dev-db)
docker run -d --name sprout-dev-db -p 5432:5432 -e POSTGRES_USER=sprout -e POSTGRES_PASSWORD=sprout -e POSTGRES_DB=sprout postgres:16-alpine
```

**Backend** (http://localhost:8000/api/docs)
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

> Port 5432 is busy? Stop the deployed app's database (`docker compose stop db`) or remove the dev one (`docker rm -f sprout-dev-db`).

---

## 4. Tests (run before pushing)

```bash
cd backend
pytest -q                       # uses SQLite by default (activate .venv first)
cd ../frontend
npm test
cd ..
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

## 6. Troubleshooting

| Problem | Try |
|---|---|
| `failed to connect to the docker API` | Start Docker Desktop and wait until it says "Engine running" |
| Port 8081 / 8090 already in use | Change `JENKINS_PORT` in `ci/.env`, or `APP_PORT` (e.g. PowerShell: `$env:APP_PORT=8095`) |
| Build fails at **Test** | Open Console Output and fix the failing test; nothing was deployed |
| Build fails at **Smoke test** | Jenkins rolls back to the previous version automatically; check `docker compose logs backend` |
| Backend can't log in to Postgres | The password in use differs from the one in the volume (see the note in section 2) |
| Clean up old images | `docker image prune -f` |
