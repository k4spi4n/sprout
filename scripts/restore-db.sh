#!/bin/sh
# Restore ONLY to an existing, empty database. Never drops or overwrites live data.
set -eu
. scripts/compose.sh
archive="${1:?Usage: RESTORE_DATABASE=empty_db sh scripts/restore-db.sh backup.dump}"
target="${RESTORE_DATABASE:?Set RESTORE_DATABASE to an existing empty database}"
case "$target" in *[!a-zA-Z0-9_]*|'') echo "Invalid database name" >&2; exit 1;; esac
sql="SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema')"
tables=$(compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$1" -Atc "$2"' sh "$target" "$sql")
[ "$tables" = 0 ] || { echo "Refusing restore: target database is not empty" >&2; exit 1; }
compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$1" --exit-on-error --single-transaction --no-owner --no-acl' sh "$target" < "$archive"
echo "Restore completed in $target; verify application data before switching traffic."
