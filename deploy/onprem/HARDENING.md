# Security hardening & review pack (Tier 2.3 / 2.4)

What an enterprise/biotech security review will ask for, and how FoldForge on-prem
answers it. Pair with SUPPORT.md (boundary) and the architecture docs.

## Posture summary

- **Data never leaves the customer.** The whole stack runs in the customer's
  environment; designed sequences + artifacts stay in their Postgres + object store.
- **No public exposure by default.** Gateway/console bind behind the customer's own
  ingress/VPN; GPU sidecars speak plaintext gRPC reachable ONLY via SSH tunnel (never a
  public port / open security group). See RUNPOD-DEPLOY.md.
- **Tenant isolation in-app.** Workflows carry an owner; the gateway forwards the
  caller's principal and the orchestrator scopes every read/mutation + artifact download.
- **License is offline + asymmetric.** Ed25519; only the public key ships. No phone-home.

## Secrets (Tier 2.3)

Today: secrets are in `deploy/onprem/.env` (gitignored). For a security review that
flags plaintext env files, support the customer's secret manager WITHOUT changing the
app — Compose reads the same variables regardless of source:
- **Docker secrets / their orchestrator's secret store:** inject as env at runtime.
- **HashiCorp Vault / sealed-secrets / cloud KMS:** render `.env` at deploy time from
  their store (e.g. `vault kv get` in the deploy step), never commit it.
- **Rotation:** `API_TOKEN`, `POSTGRES_PASSWORD`, `MINIO_*` rotate by updating the
  source + `up -d`; the license key rotates via a re-issued key (LICENSE-OPS.md).
The app requires no plaintext-on-disk secret beyond what Compose passes as env; point
that env at their manager.

## SBOM (Tier 2.4)

Generate a Software Bill of Materials per released image so the customer's scanner can
ingest it. With Syft (or `docker sbom`):
```bash
syft ghcr.io/foldforge/orchestrator:v0.1.0 -o spdx-json > sbom/orchestrator-v0.1.0.spdx.json
syft ghcr.io/foldforge/gateway:v0.1.0      -o spdx-json > sbom/gateway-v0.1.0.spdx.json
syft ghcr.io/foldforge/console:v0.1.0      -o spdx-json > sbom/console-v0.1.0.spdx.json
```
Ship the SBOMs with the release. Language manifests already pin versions (Cargo.lock,
package-lock) so the SBOM is reproducible. (Wiring SBOM generation into the release CI
is a follow-up — today it's a documented manual step at release time.)

## Vulnerability scanning

- The customer's Harbor likely runs Trivy and can block high-severity-CVE pulls
  (INSTALL.md §4) — so released images must pass their threshold.
- Vendor side: scan before tagging a release (`trivy image ...`); rebuild on a refreshed
  base image to clear base-OS CVEs before cutting `vX.Y.Z`.

## Hardening checklist (deployment)

- [ ] Gateway/console NOT on a public IP — behind ingress/VPN only.
- [ ] GPU sidecars reachable only via SSH tunnel (no public gRPC port).
- [ ] Strong `API_TOKEN` + `POSTGRES_PASSWORD` + `MINIO_*` (not the example values).
- [ ] `.env` rendered from the customer's secret manager, not committed.
- [ ] `FOLDFORGE_VERSION` pinned (never `latest`).
- [ ] TLS terminated in front of the gateway/console by the customer's ingress.
- [ ] Backups scheduled (backup.sh) + restore tested (UPGRADE.md).
- [ ] Container runtime + GPU drivers patched (customer-owned, SUPPORT.md).

## Known gaps (honest)

- SBOM generation is manual at release (not yet in CI).
- No app-level encryption-at-rest beyond what the customer's disk/DB/object store
  provide — document their at-rest encryption as the control.
- Migration pre-flight (refuse known-dangerous migration) not yet built (UPGRADE.md).
