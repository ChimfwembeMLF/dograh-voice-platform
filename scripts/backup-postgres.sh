#!/usr/bin/env bash
# Backup bundled Postgres from the Dograh compose stack.
# Usage: ./scripts/backup-postgres.sh [backup_dir]
set -euo pipefail

BACKUP_DIR="${1:-./backups}"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
CONTAINER="${POSTGRES_CONTAINER:-}"

mkdir -p "$BACKUP_DIR"

if [[ -z "$CONTAINER" ]]; then
  CONTAINER="$(docker ps -qf 'name=postgres' | head -1)"
fi

if [[ -z "$CONTAINER" ]]; then
  echo "No postgres container found. Set POSTGRES_CONTAINER or start the stack."
  exit 1
fi

DB_NAME="${POSTGRES_DB:-dograh-db}"
OUT_FILE="${BACKUP_DIR}/dograh-${TIMESTAMP}.sql.gz"

echo "Backing up ${DB_NAME} from container ${CONTAINER} → ${OUT_FILE}"
docker exec "$CONTAINER" pg_dump -U postgres "$DB_NAME" | gzip > "$OUT_FILE"
echo "Done: $(du -h "$OUT_FILE" | awk '{print $1}')"
