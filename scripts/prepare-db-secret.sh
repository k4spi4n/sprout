#!/bin/sh
# Materialize a Jenkins/host credential on the Docker host, without bind-mounting
# the agent workspace or putting the password in any container's Config.Env.
set -eu
. scripts/compose.sh
: "${POSTGRES_PASSWORD:?Inject POSTGRES_PASSWORD from the credential store}"
[ "${#POSTGRES_PASSWORD}" -ge 20 ] || { echo "Database password must contain at least 20 characters" >&2; exit 1; }
case "$POSTGRES_PASSWORD" in [Cc][Hh][Aa][Nn][Gg][Ee]-[Mm][Ee]*) echo "Replace the example password" >&2; exit 1;; esac
image=postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea
project="${APP_PROJECT:-sprout}"

# Reject an incorrect credential before changing the secret used by an old release.
if [ -n "$(compose ps -q --status running db)" ]; then
    printf '%s' "$POSTGRES_PASSWORD" | docker run --rm -i --network "${project}_data" \
        --cap-drop ALL --security-opt no-new-privileges:true --read-only \
        --entrypoint sh "$image" -c \
        'export PGPASSWORD="$(cat)"; exec psql -h db -U "$1" -d "$2" -v ON_ERROR_STOP=1 -Atc "SELECT 1"' \
        sh "${POSTGRES_USER:-sprout}" "${POSTGRES_DB:-sprout}" > /dev/null
fi

# Compose creates and labels the volume. The writer receives the password on stdin
# and atomically installs the file; app/database containers only mount it read-only.
docker volume create --label "com.docker.compose.project=$project" \
    --label com.docker.compose.volume=db_credentials "${project}_db_credentials" > /dev/null
printf '%s' "$POSTGRES_PASSWORD" | docker run --rm -i --user 0:0 \
    --network none --read-only --cap-drop ALL --security-opt no-new-privileges:true \
    --mount "type=volume,source=${project}_db_credentials,target=/secrets" \
    --entrypoint sh "$image" -c \
    'umask 077; mkdir -p /secrets; chmod 755 /secrets; cat > /secrets/db_password.next; chmod 444 /secrets/db_password.next; mv /secrets/db_password.next /secrets/db_password'
