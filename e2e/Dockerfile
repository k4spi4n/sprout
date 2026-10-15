FROM python:3.12-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /e2e
COPY requirements.txt .
RUN pip install --require-hashes -r requirements.txt
COPY . .
# JUnit report is copied out by Jenkins from /e2e/reports
CMD ["pytest", "-v", "--junitxml=reports/junit.xml"]
