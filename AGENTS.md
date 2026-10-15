# Repository Guidelines

## Project Structure & Module Organization

Sprout is a houseplant care tracker built with React/Vite, FastAPI, and PostgreSQL.

- `backend/app/`: API routes, SQLAlchemy models, schemas, and database configuration.
- `backend/tests/`: pytest suites; `backend/migrations/`: Alembic revisions.
- `frontend/src/`: React components, styles, API helpers, and colocated tests; shared test utilities live in `src/test/`.
- `e2e/`: HTTP tests through nginx, the API, and PostgreSQL.
- `scripts/`: deployment, smoke checks, dependency locking, and database recovery.
- `ci/` and `Jenkinsfile`: Jenkins configuration and pipeline; `docs/`: deployment and verification guides.

## Build, Test, and Development Commands

Run Compose commands from the repository root:

- `docker compose up -d --build --wait --wait-timeout 180`: build and start the app at `http://localhost:8090`.
- `docker compose stop`: stop services while preserving data.
- In `backend/`, install dependencies with `pip install --require-hashes -r requirements-dev.txt`; run `alembic upgrade head`, then `uvicorn app.main:app --reload`.
- In `frontend/`, run `npm ci`, then `npm run dev` for Vite or `npm run build` for production assets.

Use Python 3.12+ and Node 24.15+ (24.x) for local development.

## Coding Style & Naming Conventions

Follow existing conventions: Python uses four-space indentation and `snake_case`; JavaScript/JSX uses two spaces, single quotes, and no semicolons. React components use PascalCase filenames, such as `PlantForm.jsx`. No dedicated formatter or lint command is configured; Jenkins runs SonarQube analysis. Follow `.gitattributes`: LF generally, CRLF for `.ps1` and `.cmd`.

## Testing Guidelines

Run `pytest -q` from `backend/`; run `npm run test:ci` from `frontend/` for Vitest, React Testing Library, coverage, and JUnit output. Name Python tests `test_*.py` and frontend tests `*.test.js` or `*.test.jsx`. CI enforces 80% backend coverage and 80% frontend statement, branch, function, and line coverage.

For PostgreSQL-backed tests, run `docker compose -p sprout-test -f docker-compose.test.yml run --build --rm backend-tests`. Add regression coverage for changed behavior; use disposable databases for end-to-end tests.

## Commit & Pull Request Guidelines

Use short-lived branches and imperative commit subjects, matching history: `Fix SonarQube findings` or `Add ...`. Follow `CONTRIBUTING.md`: describe behavior and validation, obtain independent review, and pass Jenkins and SonarQube gates. Include Alembic revisions for schema changes, regenerate dependency locks when inputs change, and update `docs/DEPLOYMENT.md` when release or recovery procedures change. Keep credentials and database backups out of commits.
