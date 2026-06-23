#!/usr/bin/env bash
# Build + push a FoldForge GPU sidecar image to GHCR. Run this ON a GPU/CUDA box that
# can build the heavy model image (a RunPod Pod, an AWS g5, any CUDA host with Docker).
#
# Usage:
#   ./build-gpu-sidecar.sh <model> [tag]
#     <model> = af2 | rfdiffusion | proteinmpnn | boltz   (or 'all')
#     [tag]   = image tag (default: gpu)
#
# Examples:
#   ./build-gpu-sidecar.sh af2                 # → ghcr.io/foldforge/sidecar-af2:gpu
#   ./build-gpu-sidecar.sh rfdiffusion v1      # → ghcr.io/foldforge/sidecar-rfdiffusion:v1
#   ./build-gpu-sidecar.sh all                 # build + push all four
#
# This script does NOT log you in to GHCR or handle credentials. Authenticate first,
# the same read/write-token way as the EC2 host:
#   echo "$GHCR_PAT" | docker login ghcr.io -u <you> --password-stdin
# (a token with write:packages to push). The script verifies you're logged in and bails
# with a clear message if not — it never embeds or prompts for a secret.
#
# It expects the sidecar repos checked out as SIBLINGS of the infra repo (run
# scripts/clone-all.sh from the foldforge repo first), with the proto submodule
# populated (the Dockerfile.gpu's gen_proto.sh needs the .proto files).
set -euo pipefail

REGISTRY="ghcr.io/foldforge"
MODEL="${1:-}"
TAG="${2:-gpu}"

if [[ -z "$MODEL" ]]; then
  echo "usage: $0 <af2|rfdiffusion|proteinmpnn|boltz|all> [tag]" >&2
  exit 2
fi

# infra/scripts/ -> infra -> parent holds the sibling repos.
PARENT="$(cd "$(dirname "$0")/../.." && pwd)"

# --- preflight: docker present + logged in to GHCR -----------------------------
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found on PATH." >&2; exit 1; }
# A logged-in client has an auth entry for ghcr.io in its config. Don't print it.
if ! docker system info >/dev/null 2>&1; then
  echo "ERROR: docker daemon not reachable." >&2; exit 1
fi
if ! grep -q "ghcr.io" "${DOCKER_CONFIG:-$HOME/.docker}/config.json" 2>/dev/null; then
  echo "ERROR: not logged in to ghcr.io. Run:" >&2
  echo '  echo "$GHCR_PAT" | docker login ghcr.io -u <you> --password-stdin' >&2
  exit 1
fi

build_one() {
  local model="$1"
  local repo="$PARENT/sidecar-$model"
  local img="$REGISTRY/sidecar-$model:$TAG"

  echo "==> sidecar-$model"
  [[ -d "$repo" ]] || { echo "  ERROR: $repo not found (run clone-all.sh first)." >&2; return 1; }
  [[ -f "$repo/Dockerfile.gpu" ]] || { echo "  ERROR: $repo/Dockerfile.gpu missing." >&2; return 1; }

  # proto submodule must be populated (gen_proto.sh needs the .proto files).
  if [[ ! -f "$repo/proto/foldforge/common/v1/common.proto" ]]; then
    echo "  proto submodule empty — initializing"
    git -C "$repo" submodule update --init --recursive
  fi

  echo "  building $img (first build iterates on version pins — see Dockerfile.gpu STATUS)"
  docker build -f "$repo/Dockerfile.gpu" -t "$img" "$repo"
  echo "  pushing $img"
  docker push "$img"
  echo "  done: $img"
}

if [[ "$MODEL" == "all" ]]; then
  for m in af2 rfdiffusion proteinmpnn boltz; do build_one "$m"; done
else
  case "$MODEL" in
    af2|rfdiffusion|proteinmpnn|boltz) build_one "$MODEL" ;;
    *) echo "ERROR: unknown model '$MODEL' (af2|rfdiffusion|proteinmpnn|boltz|all)" >&2; exit 2 ;;
  esac
fi

echo "ALL DONE. Deploy the image(s) as RunPod Pod(s) — see infra/docs/RUNPOD-DEPLOY.md."
