# ---- base: runtime dependencies ----
FROM python:3.12-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1 AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --require-hashes -r requirements.txt

# ---- test: used by docker-compose.test.yml (Jenkins "Unit tests" stage) ----
FROM base AS test
COPY requirements-dev.txt .
RUN pip install --require-hashes -r requirements-dev.txt
COPY . .
# Reports (coverage for SonarQube, JUnit for Jenkins) are written to /app/reports
CMD ["pytest", "-v", "--cov=app", "--cov-branch", "--cov-fail-under=80", "--cov-report=term", "--cov-report=xml:reports/coverage.xml", "--junitxml=reports/junit.xml"]

# ---- runtime: default (last) stage ----
FROM base AS runtime
# Jenkins build number baked into the image; reported by /api/health and checked by the smoke test
ARG APP_BUILD=dev
ARG APP_REVISION=unknown
ENV APP_BUILD=${APP_BUILD} APP_REVISION=${APP_REVISION}
LABEL org.opencontainers.image.title="Sprout API" \
      org.opencontainers.image.version=${APP_BUILD} \
      org.opencontainers.image.revision=${APP_REVISION}
RUN useradd --create-home --uid 10001 app
COPY app ./app
COPY alembic.ini .
COPY migrations ./migrations
USER app
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/health')"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header", "--timeout-graceful-shutdown", "20"]
