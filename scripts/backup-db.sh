#!/bin/sh
# Custom-format PostgreSQL dump; never print credentials or archive this as a CI artifact.
set -eu
. scripts/compose.sh
umask 077
destination="${1:?Usage: sh scripts/backup-db.sh path/to/backup.dump}"
[ ! -e "$destination" ] || { echo "Backup already exists: $destination" >&2; exit 1; }
mkdir -p "$(dirname "$destination")"
trap 'rm -f "$destination.partial"' EXIT HUP INT TERM
compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl' > "$destination.partial"
# Verify the archive can be read before replacing the final filename.
compose exec -T db pg_restore --list < "$destination.partial" > /dev/null
mv "$destination.partial" "$destination"
echo "Database backup verified: $destination"
