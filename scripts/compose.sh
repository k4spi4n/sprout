#!/bin/sh
# Shared Compose selection; COMPOSE_FILE supports colon-separated overrides on Linux.
set -eu
compose() {
    docker compose -p "${APP_PROJECT:-sprout}" "$@"
}

smoke() {
    docker run --rm -i --network "${APP_PROJECT:-sprout}_default" \
        --cap-drop ALL --security-opt no-new-privileges:true --read-only \
        --entrypoint sh \
        curlimages/curl@sha256:a134550be58ab783810e613ae96fd253c38f7bdd16d9bf9be350700c7a29ac06 \
        -s -- http://frontend:8080 "$1" < scripts/smoke-test.sh
}
