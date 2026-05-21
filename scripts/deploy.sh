#!/usr/bin/env bash
# Deploy / update the FoldForge stack on the app node.
# Usage (run on the app node, or via ssh): ./scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/../compose"

if [[ ! -f .env ]]; then
  echo "ERROR: compose/.env missing. Copy .env.example and fill secrets." >&2
  exit 1
fi

echo "==> pulling pinned images"
docker compose pull

echo "==> starting stack"
docker compose up -d

echo "==> waiting for gateway health"
for i in {1..30}; do
  if curl -fsS localhost:8080/v1/healthz >/dev/null 2>&1; then
    echo "OK: gateway healthy"
    docker compose ps
    exit 0
  fi
  sleep 2
done
echo "ERROR: gateway did not become healthy" >&2
docker compose logs --tail 50 gateway
exit 1
