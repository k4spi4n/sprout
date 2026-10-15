#!/bin/sh
# Read-only post-deploy checks (never writes to the production database).
# Usage: smoke-test.sh <base-url> <expected-build>
# Jenkins pipes this into a curl container on the app network:
#   docker run --rm -i --network sprout_default --entrypoint sh curlimages/curl -s -- http://frontend 42 < scripts/smoke-test.sh
set -eu
curl() { command curl --connect-timeout 3 --max-time 10 "$@"; }
BASE="$1"
EXPECTED="$2"

fail() { echo "SMOKE TEST FAILED: $*"; exit 1; }
ok()   { echo "  ok  $*"; }

echo "Smoke testing $BASE (expecting build $EXPECTED)"

i=0
until health=$(curl -fsS "$BASE/api/health" 2>/dev/null); do
  i=$((i + 1))
  [ "$i" -ge 30 ] && fail "/api/health not reachable after 60s"
  sleep 2
done
echo "$health" | grep -q '"database":"ok"' || fail "database not connected: $health"
ok "API healthy, database connected"
echo "$health" | grep -Fq "\"build\":\"$EXPECTED\"" || fail "expected build $EXPECTED to be live, got: $health"
ok "build $EXPECTED is live"

page=$(curl -fsS "$BASE/") || fail "frontend not reachable"
echo "$page" | grep -q 'id="root"' || fail "index.html has no app root"
ok "frontend serves index.html"

bundle=$(echo "$page" | grep -o '/assets/[^"]*\.js' | head -n 1)
[ -n "$bundle" ] || fail "index.html references no JS bundle"
curl -fsS -o /dev/null "$BASE$bundle" || fail "JS bundle $bundle not served"
ok "JS bundle $bundle served"

plants=$(curl -fsS "$BASE/api/plants") || fail "GET /api/plants failed"
case "$plants" in
  \[*) ok "GET /api/plants returns a list" ;;
  *) fail "unexpected /api/plants response: $plants" ;;
esac

curl -fsS -o /dev/null "$BASE/api/docs" || fail "/api/docs not served"
ok "API docs served"

echo "Smoke test passed"
