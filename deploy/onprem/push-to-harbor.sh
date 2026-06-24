#!/usr/bin/env bash
# Push FoldForge images into a CUSTOMER's Harbor (delivery model B). Pulls each image
# from the SOURCE (our build registry, GHCR) at a pinned version, re-tags it for the
# customer's Harbor project, and pushes. The customer then runs docker-compose.onprem.yml
# with FOLDFORGE_REGISTRY = their Harbor project.
#
# Usage:
#   ./push-to-harbor.sh <harbor-project> <version> [source-registry]
#     <harbor-project>  e.g. harbor.acme.internal/foldforge   (NO trailing slash)
#     <version>         e.g. v0.1.0                            (the released tag)
#     [source-registry] default ghcr.io/foldforge
#
# Prereqs (you do these — credentials are yours, the script never embeds them):
#   - Logged in to the SOURCE:   docker login ghcr.io
#   - Logged in to the CUSTOMER Harbor:  docker login harbor.acme.internal
#     (Harbor is almost always TLS; if its cert is signed by an internal CA, add that CA
#      to docker's trust first — see INSTALL.md "Harbor TLS / internal CA".)
#
# This pushes the CONTROL-PLANE images. GPU sidecar images are large and pushed the
# same way when GPU nodes are in scope: add them to IMAGES below.
set -euo pipefail

HARBOR="${1:-}"
VERSION="${2:-}"
SOURCE="${3:-ghcr.io/foldforge}"

if [[ -z "$HARBOR" || -z "$VERSION" ]]; then
  echo "usage: $0 <harbor-project> <version> [source-registry]" >&2
  echo "  e.g. $0 harbor.acme.internal/foldforge v0.1.0" >&2
  exit 2
fi

# Control-plane images. Add sidecar-<model> here when delivering GPU nodes.
IMAGES=(orchestrator gateway console)

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }
docker system info >/dev/null 2>&1 || { echo "ERROR: docker daemon not reachable." >&2; exit 1; }

# Verify login to BOTH registries (don't print auth). A logged-in client has a config
# entry for the registry host.
cfg="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
src_host="${SOURCE%%/*}"
harbor_host="${HARBOR%%/*}"
grep -q "$src_host" "$cfg" 2>/dev/null   || { echo "ERROR: not logged in to source $src_host (docker login $src_host)." >&2; exit 1; }
grep -q "$harbor_host" "$cfg" 2>/dev/null || { echo "ERROR: not logged in to Harbor $harbor_host (docker login $harbor_host)." >&2; exit 1; }

echo "==> delivering FoldForge $VERSION  $SOURCE → $HARBOR"
for svc in "${IMAGES[@]}"; do
  src="$SOURCE/$svc:$VERSION"
  dst="$HARBOR/$svc:$VERSION"
  echo "-- $svc"
  echo "   pull  $src"
  docker pull "$src"
  echo "   tag   $dst"
  docker tag "$src" "$dst"
  echo "   push  $dst"
  docker push "$dst"
done

echo "DONE. On the customer host set FOLDFORGE_REGISTRY=$HARBOR + FOLDFORGE_VERSION=$VERSION"
echo "in deploy/onprem/.env, then: docker compose -f docker-compose.onprem.yml up -d"
