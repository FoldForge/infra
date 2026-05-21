#!/usr/bin/env bash
# One-time: create the R2 bucket that holds Terraform remote state.
# Requires wrangler (npm i -g wrangler) authenticated to the FoldForge account.
set -euo pipefail
BUCKET="${1:-foldforge-tfstate}"
echo "Creating R2 bucket: $BUCKET"
wrangler r2 bucket create "$BUCKET"
echo "Done. Now: terraform init -backend-config=backend.hcl"
