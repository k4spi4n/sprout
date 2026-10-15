# Deployment and recovery runbook

Sprout uses the mentor's `../cicd-portal` flow: checkout, parallel unit tests,
SonarQube analysis, a separate Quality Gate, image build, registry push, deployment
with injected credentials, and smoke tests. Sprout adds image scanning, an SBOM,
release-image integration tests, versioned migrations, pre-deploy backups and
verified application rollback. The FastAPI/React toolchain runs in Docker, so Maven
and a Jenkins-managed Node installation are unnecessary.

## Prerequisites and portal configuration

Use Docker Engine/Desktop with Compose >= 2.30 (for the `!reset` overrides),
Git, and a Linux Jenkins agent with Docker CLI,
Compose, `curl` and `tar`. Local frontend work uses Node 24.15+; backend work uses
Python 3.12+. The dependency locks include platform markers for Windows and Linux.

Either use the existing mentor portal or build `ci/docker-compose.jenkins.yml`.
The latter remains an optional reproducible JCasC bootstrap; it installs pinned
plugins and SonarScanner. It is not required when using an existing Jenkins server.
Bind Jenkins and SonarQube administration to localhost or a private management
network. Do not expose the controller or its Docker socket to untrusted jobs.

On the portal configure these exact names:

| Type | Name / ID | Configuration |
|---|---|---|
| SonarQube server | `SonarQube` | Reachable URL from Jenkins, e.g. `http://sonarqube:9000`; credential `sonar-token` |
| SonarScanner tool | `sonar-scanner` | Install in Manage Jenkins > Tools; the bundled CI image instead sets `SPROUT_SCANNER_HOME=/opt/sonar-scanner` |
| Secret text | `sonar-token` | Expiring project analysis token for a dedicated CI user with Execute Analysis on `sprout` |
| Username/password | `registry-credentials` | Docker Hub username and access token; needed only with `PUSH_IMAGE=true` |
| Secret text | `sprout-db-password` | Unique PostgreSQL password, at least 20 characters; must match the existing database |
| Git credential | `git-credentials` | Read-only repository token, selected in the job for private repositories |

Install Pipeline, Git, Credentials Binding, JUnit, Timestamper and SonarQube Scanner
plugins. On SonarQube, manually change the initial admin password, create project
`sprout`, create the CI analysis user/token, configure the new-code Quality Gate
described in [CONTRIBUTING.md](../CONTRIBUTING.md), and add webhook
`http://jenkins:8080/sonarqube-webhook/` (trailing slash required). For the mentor
stack this internal URL works because Jenkins and SonarQube share its network.
The pipeline never needs the SonarQube administrator password.

For bundled JCasC, copy `ci/.env.example` to `ci/.env`, set the repository URL and
strong passwords, start the CI stack, complete the SonarQube portal setup, then set
`SPROUT_SONAR_TOKEN` and recreate Jenkins. Existing `SONAR_ADMIN_PASSWORD` values
are no longer used. Registry credential ID is now `registry-credentials`.

Create a separate Pipeline-from-SCM job with script path `ci/selftest.Jenkinsfile`
to check tools, Docker connectivity and analysis/deployment credentials. Then
create the application job with script path `Jenkinsfile` and configure its SCM
branch as `*/main`; the release stage also rejects other branches
and change-request builds. Build/publish validation may run without deployment.
For initial validation,
use `DEPLOY=false`, `PUSH_IMAGE=false`; this still builds, scans and integration
tests the release. Select `IMAGE_NAMESPACE` for your Docker Hub user/organisation
and enable `PUSH_IMAGE` when publishing. `DEPLOY=true` performs the release after
all gates pass. Polling runs only while Jenkins is running.

## Local development and tests

```sh
docker compose up -d --build --wait --wait-timeout 180
# http://localhost:8090 and http://localhost:8090/api/docs
docker compose stop

# Development backend (from backend/):
python -m pip install --require-hashes -r requirements-dev.txt
alembic upgrade head
uvicorn app.main:app --reload

# Frontend (from frontend/):
npm ci
npm test
npm run build

# Disposable real-PostgreSQL unit tests:
docker compose -p sprout-test -f docker-compose.test.yml run --build --rm backend-tests
docker compose -p sprout-test -f docker-compose.test.yml run --build --rm frontend-tests
docker compose -p sprout-test -f docker-compose.test.yml down -v
```

The API no longer modifies tables during startup. Compose runs the `migrate`
service once before starting the backend. `/api/live` checks process liveness;
`/api/health` returns 503 when PostgreSQL or the schema revision is not ready.
Tests drop and recreate their schema. An externally supplied `DATABASE_URL` also
requires `SPROUT_TEST_DATABASE=1`; use this only for a disposable database.

Regenerate all Python locks using `uv==0.13.1` and
`sh scripts/lock-dependencies.sh` from the root. Review direct dependencies in
`backend/requirements*.in` and `e2e/requirements.in`; commit the generated hashes.
Run `pip-audit --strict` in the test image and `npm audit --audit-level=moderate`
in the frontend. CI additionally scans secrets and fails on fixable HIGH/CRITICAL
image vulnerabilities using Trivy. Unfixed image findings need operational review;
the image gate's `--ignore-unfixed` option is explicit in the Jenkinsfile.
Refresh base-image digests and the pinned Jenkins plugin inventory regularly.

## Production release

The default stack stays local and on demand. Production adds mounted password
secrets, required image references, and `unless-stopped` restarts via
`docker-compose.production.yml`. The release helper writes the injected credential
via stdin into a private Docker volume, mounted read-only at `/run/secrets` by the
database, migration and backend services. This supports both read-only containers
and Jenkins' host Docker socket without exposing passwords in container configuration
or requiring host access to Jenkins' workspace. Docker volumes do not encrypt
the host storage; protect the Docker daemon and the Jenkins credential store.

Jenkins uses exact local image IDs, so integration testing and deployment use the
same bytes. Published tags contain the build number and Git commit; no `latest`
tag is published. The archived manifest includes registry digest metadata for
retrieval on another host. Use repo digests for a remote/manual deployment:

```sh
export COMPOSE_FILE=docker-compose.yml:docker-compose.production.yml
export APP_PROJECT=sprout
export SPROUT_PRODUCTION=1
export IMAGE_TAG=42-0123456789ab
export APP_REVISION=<full-git-revision>
export BACKEND_IMAGE=<namespace>/sprout-backend@sha256:<digest>
export FRONTEND_IMAGE=<namespace>/sprout-frontend@sha256:<digest>
# Inject POSTGRES_PASSWORD from the host's secret manager; do not commit it.
docker compose pull db backend frontend migrate
sh scripts/deploy.sh
```

The script validates immutable image references and build labels, snapshots both
previous image IDs, starts PostgreSQL, creates and checks a custom-format backup,
applies migrations, waits for health, and performs read-only smoke checks including
the expected build. It records `.releases/current.env` only on success. Do not run
two release processes against the same project. Jenkins serializes its builds;
operators must coordinate manual releases with the deployment job.

CI also runs `scripts/test-recovery.sh` against its disposable integration project:
it restores a backup and compares rows/schema, refuses a populated restore target,
then deploys a deliberately broken JS bundle and checks that smoke testing rejects
it and restores the exact previous image IDs. The helper refuses production project
names. Recovery test output is archived with the end-to-end reports.
The checkout stage additionally runs daemon-free shell regression checks with
`sh scripts/test-release-failures.sh`, including the rollback-failure state that
must block another deployment.

Backups default to `.backups/` locally and `$JENKINS_HOME/sprout-backups` in CI.
They contain application data, use restrictive permissions, and are never archived
as build artifacts. Store them on encrypted storage, copy them off-host, monitor
backup failures and space, and set retention according to the required recovery
point. This repository does not provision remote storage or a backup scheduler.

The frontend is bound to `127.0.0.1:8090`. For a shared server place an HTTPS reverse
proxy in front, configure DNS/certificates and access control, and configure
`APP_BIND` only for the intended interface. Sprout currently has no application
authentication; keep it private or enforce authentication at the ingress. Watch
readiness failures, API 5xx/latency, disk space, container restarts and backup age.
The single-host Compose release can briefly interrupt requests; it does not provide
rolling upgrades or high availability. Resource limits are initial budgets to tune
with measured workload data.

## First upgrade from the original base app

Revision `0001_plants` compares an existing `plants` table with the original
schema. It adopts only a matching table and preserves rows; a mismatch stops the
migration instead of silently stamping it. Back up the old database first.
Legacy images lack the labels and non-root nginx layout required for automatic
rollback. Perform this initial transition in a maintenance window using
`docker compose up -d --build --wait`, verify existing plants, and retain the old
image/Compose files and backup for manual recovery. Subsequent releases support
the automatic rollback workflow. Never remove `pgdata` to change a password.

## Rollback and restore drill

On failed startup, migration or smoke checks, the release script restores both
previous application images and verifies their health/build. Jenkins additionally
attempts rollback for unsuccessful or aborted builds when a pending marker
remains. A hard host/controller failure can interrupt recovery; after restarting
the agent, use the same project, Compose files and database credential:

```sh
sh scripts/deploy.sh rollback
```

Rollback does not downgrade the schema or restore an old dump automatically.
Migrations must remain compatible with the previous app. Destructive schema work
requires its own reviewed maintenance/recovery plan. A first-release failure stops
the app and preserves PostgreSQL. A failed rollback leaves `.releases/pending`
in place and blocks another deployment until an operator resolves it.

To prove a dump is restorable, restore it into a separate **empty** database:

```sh
sh scripts/backup-db.sh .backups/restore-drill.dump
docker compose exec db sh -c 'createdb -U "$POSTGRES_USER" sprout_restore_drill'
RESTORE_DATABASE=sprout_restore_drill sh scripts/restore-db.sh .backups/restore-drill.dump
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d sprout_restore_drill -c "SELECT count(*) FROM plants"'
```

The restore helper refuses a nonempty target and uses a single transaction with
exit-on-error. Verify the schema revision, representative rows and API against
the restored database before any traffic switch. Record restore time and data
loss against the required RTO/RPO; a verified archive listing alone is not a restore
drill. Keep the source database intact until recovery is approved and verified.
