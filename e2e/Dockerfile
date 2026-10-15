FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /e2e
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
# JUnit report is copied out by Jenkins from /e2e/reports
CMD ["pytest", "-v", "--junitxml=reports/junit.xml"]
