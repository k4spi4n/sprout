#!/bin/sh
# Exercises real dump/restore and a failed release against a disposable CI stack.
set -eu
. scripts/compose.sh
case "${APP_PROJECT:-}" in sprout-it-*|sprout-hardening-*) ;; *) echo "Recovery tests require an isolated CI project" >&2; exit 1;; esac
: "${IMAGE_TAG:?Set the release build identity}"
: "${FRONTEND_IMAGE:?Set the tested frontend image ID}"
work=$(mktemp -d)
created=0
probe="sprout-rollback-probe:$IMAGE_TAG"
backend_probe="sprout-rollback-backend:$IMAGE_TAG"
cleanup() {
    if [ "$created" = 1 ]; then
        compose exec -T db sh -c 'dropdb -U "$POSTGRES_USER" sprout_restore_drill' || true
    fi
    docker image rm "$probe" > /dev/null 2>&1 || true
    docker image rm "$backend_probe" > /dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 143' TERM HUP
trap 'exit 130' INT

expected=$(compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT count(*) FROM plants"')
[ "$expected" -gt 0 ] || { echo "Run e2e tests first to create representative data" >&2; exit 1; }
sh scripts/backup-db.sh "$work/restore.dump"
compose exec -T db sh -c 'createdb -U "$POSTGRES_USER" sprout_restore_drill'
created=1
RESTORE_DATABASE=sprout_restore_drill sh scripts/restore-db.sh "$work/restore.dump"
actual=$(compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d sprout_restore_drill -Atc "SELECT count(*) FROM plants"')
[ "$expected" = "$actual" ] || { echo "Restored row count differs" >&2; exit 1; }
version=$(compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d sprout_restore_drill -Atc "SELECT version_num FROM alembic_version"')
[ -n "$version" ] || { echo "Restored migration revision is missing" >&2; exit 1; }
if RESTORE_DATABASE=sprout_restore_drill sh scripts/restore-db.sh "$work/restore.dump"; then
    echo "Restore incorrectly accepted a populated database" >&2; exit 1
fi
echo "PASS: backup restored with data/schema intact; populated target refused"

# Break a JS asset while keeping API/container health green: smoke must catch it.
old_frontend=$FRONTEND_IMAGE
old_backend=$BACKEND_IMAGE
printf '%s\n' 'ARG BASE_IMAGE=nginx:stable-alpine' 'FROM ${BASE_IMAGE}' 'USER root' \
    'RUN rm -f /usr/share/nginx/html/assets/*.js' 'USER nginx' | \
    docker build --build-arg "BASE_IMAGE=${IMAGE_NAMESPACE:-local}/sprout-frontend:$IMAGE_TAG" -t "$probe" -
FRONTEND_IMAGE=$(docker image inspect --format '{{.Id}}' "$probe")
printf '%s\n' 'ARG BASE_IMAGE=python:3.12-slim' 'FROM ${BASE_IMAGE}' \
    'LABEL org.sprout.recovery-test=true' | \
    docker build --build-arg "BASE_IMAGE=${IMAGE_NAMESPACE:-local}/sprout-backend:$IMAGE_TAG" -t "$backend_probe" -
BACKEND_IMAGE=$(docker image inspect --format '{{.Id}}' "$backend_probe")
export BACKEND_IMAGE FRONTEND_IMAGE RELEASE_STATE_DIR="$work/release" BACKUP_DIR="$work/backups"
if sh scripts/deploy.sh; then
    echo "Release incorrectly accepted a missing JS bundle" >&2; exit 1
fi
FRONTEND_IMAGE=$old_frontend
BACKEND_IMAGE=$old_backend
export BACKEND_IMAGE FRONTEND_IMAGE
backend=$(docker inspect --format '{{.Image}}' "$(compose ps -q backend)")
frontend=$(docker inspect --format '{{.Image}}' "$(compose ps -q frontend)")
[ "$backend" = "$old_backend" ] && [ "$frontend" = "$old_frontend" ] || { echo "Previous image IDs were not restored" >&2; exit 1; }
[ ! -f "$RELEASE_STATE_DIR/pending" ] || { echo "Rollback did not complete" >&2; exit 1; }
smoke "$IMAGE_TAG"
echo "PASS: broken release rejected and both previous images restored and verified"
