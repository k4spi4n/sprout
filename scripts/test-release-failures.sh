#!/bin/sh
# Regression checks for recovery failures. Docker is replaced by a private stub;
# this script never accesses a real daemon, container, database or credential.
set -eu
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 143' HUP TERM
trap 'exit 130' INT
mkdir -p "$work/bin" "$work/project"
cp -R scripts "$work/project/scripts"
cat > "$work/bin/docker" <<'STUB'
#!/bin/sh
case "$*" in
    'image inspect --format '*) echo ci-test ;;
    'image inspect '*) exit 0 ;;
    'inspect --format '*previous-backend) echo sha256:previous-backend ;;
    'inspect --format '*previous-frontend) echo sha256:previous-frontend ;;
    *'ps -aq backend') [ "${NO_PREVIOUS:-0}" = 1 ] || echo previous-backend ;;
    *'ps -aq frontend') [ "${NO_PREVIOUS:-0}" = 1 ] || echo previous-frontend ;;
    *'config --quiet') exit 0 ;;
    *'exec -T db sh -c '*) echo fake-dump ;;
    *'exec -T db pg_restore --list') exit 0 ;;
    *'up '*--no-deps*) [ "${ALLOW_RECOVERY:-0}" = 1 ] ;;
    *'up '*db\ migrate\ backend\ frontend) exit 42 ;;
    *'up '*db) exit 0 ;;
    *'stop backend frontend') exit 0 ;;
    'run '*) [ "${ALLOW_RECOVERY:-0}" = 1 ] ;;
    *) echo "Unexpected Docker operation in regression test: $*" >&2; exit 99 ;;
esac
STUB
chmod 700 "$work/bin/docker"
export PATH="$work/bin:$PATH" IMAGE_TAG=ci-test BACKEND_IMAGE=sha256:candidate-backend FRONTEND_IMAGE=sha256:candidate-frontend
export SPROUT_PRODUCTION=0 APP_PROJECT=sprout-script-regression
cd "$work/project"
rc=0
sh scripts/deploy.sh > failure.log 2>&1 || rc=$?
if [ "$rc" -ne 42 ] || [ ! -f .releases/pending ]; then
    cat failure.log
    echo 'Failed rollback must preserve the pending marker and original failure' >&2
    exit 1
fi
if sh scripts/deploy.sh > retry.log 2>&1; then
    echo 'A new release must be blocked until recovery completes' >&2; exit 1
fi
ALLOW_RECOVERY=1 sh scripts/deploy.sh rollback
[ ! -f .releases/pending ] || { echo 'Successful recovery did not clear the marker' >&2; exit 1; }
echo 'PASS: failed rollback preserves pending state; new release blocked; explicit recovery resumes safely'

export RELEASE_STATE_DIR=.first-release NO_PREVIOUS=1 BACKUP_DIR=.first-backups
rc=0
sh scripts/deploy.sh > first-release.log 2>&1 || rc=$?
if [ "$rc" -ne 42 ] || [ -f .first-release/pending ]; then
    cat first-release.log
    echo 'First-release recovery must stop only the application and preserve the database' >&2
    exit 1
fi
echo 'PASS: failed first release stops application services without removing database data'
