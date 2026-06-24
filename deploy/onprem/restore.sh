#!/usr/bin/env bash
# Restore FoldForge on-prem state from a backup dir made by backup.sh. DESTRUCTIVE:
# overwrites the current Postgres DB + object store. Stop the app services first so
# nothing writes mid-restore.
#
# Usage:
#   ./restore.sh <backup-dir>
set -euo pipefail
cd "$(dirname "$0")"

BACKUP="${1:-}"
[ -n "$BACKUP" ] && [ -d "$BACKUP" ] || { echo "usage: $0 <backup-dir>" >&2; exit 2; }
[ -f "$BACKUP/postgres.dump" ] || { echo "ERROR: $BACKUP/postgres.dump missing." >&2; exit 1; }

COMPOSE="docker compose -f docker-compose.onprem.yml"
set -a; [ -f .env ] && . ./.env; set +a
PGUSER="${POSTGRES_USER:-postgres}"
PGDB="${POSTGRES_DB:-foldforge}"
BUCKET="${R2_BUCKET:-foldforge}"

echo "==> stopping app services (postgres + minio stay up for the restore)"
$COMPOSE stop orchestrator gateway console || true

echo "==> restoring Postgres ($PGDB) — DROP + recreate"
# --clean --if-exists drops existing objects first; -Fc matches backup.sh's format.
$COMPOSE exec -T postgres pg_restore -U "$PGUSER" -d "$PGDB" --clean --if-exists < "$BACKUP/postgres.dump"

if [ -f "$BACKUP/artifacts.tar" ]; then
  echo "==> restoring object store (bucket $BUCKET)"
  $COMPOSE exec -T minio sh -c "
    rm -rf /tmp/ffrestore && mkdir -p /tmp/ffrestore &&
    tar -C /tmp/ffrestore -xf - &&
    mc alias set local http://localhost:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD >/dev/null &&
    mc mb --ignore-existing local/$BUCKET >/dev/null &&
    mc mirror --quiet --overwrite /tmp/ffrestore local/$BUCKET >/dev/null" < "$BACKUP/artifacts.tar" || {
      echo "  WARN: object-store restore failed — DB restored; re-check artifacts." >&2
    }
else
  echo "==> no artifacts.tar in backup — skipping object store (DB-only restore)"
fi

echo "==> restarting app services"
$COMPOSE up -d
echo "OK: restored from $BACKUP. Verify: curl localhost:\${GATEWAY_HOST_PORT:-18080}/v1/healthz"
