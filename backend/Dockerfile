# ---- base: runtime dependencies ----
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

# ---- test: used by docker-compose.test.yml (Jenkins "Unit tests" stage) ----
FROM base AS test
COPY requirements-dev.txt .
RUN pip install -r requirements-dev.txt
COPY . .
# Reports (coverage for SonarQube, JUnit for Jenkins) are written to /app/reports
CMD ["pytest", "-v", "--cov", "--cov-report=term", "--cov-report=xml:reports/coverage.xml", "--junitxml=reports/junit.xml"]

# ---- runtime: default (last) stage ----
FROM base AS runtime
# Jenkins build number baked into the image; reported by /api/health and checked by the smoke test
ARG APP_BUILD=dev
ENV APP_BUILD=${APP_BUILD}
RUN useradd --create-home --uid 10001 app
COPY app ./app
USER app
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/health')"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
