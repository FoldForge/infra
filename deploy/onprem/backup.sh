#!/usr/bin/env bash
# Back up the FoldForge on-prem state: Postgres (workflows, steps, events, billing,
# api_keys) + the object store bucket (artifacts). Run on the customer host from
# deploy/onprem/. Output: a timestamped directory under ./backups/.
#
# The DB is the source of truth for workflow/billing/license state; the object store
# holds artifact bytes. Both must be captured together for a consistent restore.
#
# Usage:
#   ./backup.sh [output-dir]      # default: ./backups/<UTC-timestamp>
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE="docker compose -f docker-compose.onprem.yml"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${1:-./backups/$TS}"
mkdir -p "$OUT"

# Load .env so we know the DB name/user + MinIO creds (do not echo secrets).
set -a; [ -f .env ] && . ./.env; set +a
PGUSER="${POSTGRES_USER:-postgres}"
PGDB="${POSTGRES_DB:-foldforge}"
BUCKET="${R2_BUCKET:-foldforge}"

echo "==> Postgres dump ($PGDB)"
# pg_dump custom format (-Fc): compressed, restorable with pg_restore, version-tolerant.
$COMPOSE exec -T postgres pg_dump -U "$PGUSER" -Fc "$PGDB" > "$OUT/postgres.dump"

echo "==> Object store (bucket $BUCKET)"
# Mirror the bucket out via the mc client in a one-shot container sharing the network.
$COMPOSE exec -T minio sh -c "
  mc alias set local http://localhost:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD >/dev/null &&
  mc mirror --quiet --overwrite local/$BUCKET /tmp/ffbackup >/dev/null &&
  tar -C /tmp/ffbackup -cf - ." > "$OUT/artifacts.tar" 2>/dev/null || {
    echo "  WARN: object-store backup skipped (mc/bucket unavailable) — DB still captured." >&2
  }

# Record the running version for restore compatibility.
echo "FOLDFORGE_VERSION=${FOLDFORGE_VERSION:-unknown}" > "$OUT/MANIFEST"
echo "taken_utc=$TS" >> "$OUT/MANIFEST"
du -sh "$OUT"/* 2>/dev/null || true
echo "OK: backup at $OUT"
echo "Restore with: ./restore.sh $OUT"
