# FoldForge on-prem install (delivery model B — customer Harbor)

The control plane runs in the customer's environment; images come from the customer's
own Harbor registry. Two roles:
- **You (vendor):** push the released images into the customer's Harbor.
- **Customer:** fill `.env`, bring the stack up, reach it via their own ingress/VPN.

The control plane is GPU-free and runs the mock runner by default, so it's demoable
before any GPU node exists. Switch to real inference by pointing `SIDECAR_*` at GPU
nodes (see `infra/docs/RUNPOD-DEPLOY.md`).

---

## 0. Prerequisites

Customer host (control plane — no GPU): Linux, Docker + Docker Compose v2, ~4 GB RAM,
outbound access to their Harbor only. The host need NOT reach the public internet.

Customer Harbor: a project for FoldForge (e.g. `foldforge`), a robot account or user
with push (for you) + pull (for the host), and — if Harbor enforces it — image scanning
that your released images pass (see §4).

## 1. Deliver images into the customer Harbor (vendor)

On a machine that can reach BOTH our build registry and the customer Harbor:

```bash
docker login ghcr.io                      # source (our builds) — your creds
docker login harbor.acme.internal         # customer Harbor — creds they issue you
infra/deploy/onprem/push-to-harbor.sh harbor.acme.internal/foldforge v0.1.0
```

This pulls `ghcr.io/foldforge/<svc>:v0.1.0`, re-tags to
`harbor.acme.internal/foldforge/<svc>:v0.1.0`, and pushes. (The script never handles
your credentials — you `docker login` first; it verifies both logins and bails clearly
if either is missing.)

### Harbor TLS / internal CA (the #1 gotcha)
Harbor is almost always TLS, often with a cert signed by the customer's INTERNAL CA. If
`docker login`/`push` fails with `x509: certificate signed by unknown authority`, add
their CA to Docker's trust on the pushing host AND the customer host:
```bash
sudo mkdir -p /etc/docker/certs.d/harbor.acme.internal
sudo cp customer-ca.crt /etc/docker/certs.d/harbor.acme.internal/ca.crt
sudo systemctl restart docker
```

## 2. Configure (customer)

```bash
cd infra/deploy/onprem
cp onprem.env.example .env
# Edit .env:
#   FOLDFORGE_REGISTRY=harbor.acme.internal/foldforge   # their Harbor project
#   FOLDFORGE_VERSION=v0.1.0                              # the delivered version
#   POSTGRES_PASSWORD / API_TOKEN / MINIO_* = strong secrets
```
NEVER use `latest` — pin the exact delivered `FOLDFORGE_VERSION` so support debugs the
same build the customer runs.

## 3. Bring up (customer)

```bash
docker login harbor.acme.internal        # the host needs pull access
docker compose -f docker-compose.onprem.yml up -d
# health:
curl -fsS localhost:${GATEWAY_HOST_PORT:-18080}/v1/healthz
```
Expose the gateway/console only behind the customer's own ingress/VPN — do not put them
on the public internet (the platform follows a no-public-plaintext posture).

## 4. Image scanning (if Harbor enforces it)
Harbor often runs Trivy and can BLOCK pulls of images with high-severity CVEs. If the
customer's project enforces this, the released images must pass their threshold. Track
base-image CVEs in CI and rebuild on a clean base before cutting a release; deliver an
image digest list so the customer can pre-approve in their scanner.

## 5. Upgrade
Deliver the new version into Harbor (§1 with the new tag), bump `FOLDFORGE_VERSION` in
`.env`, then `docker compose -f docker-compose.onprem.yml up -d` (Compose recreates only
changed services). BACK UP POSTGRES FIRST — orchestrator runs migrations on boot; an
upgrade migrates the customer's data in place. (A backup/restore + migration-rollback
runbook is the next on-prem hardening item — see PRIVATE-DEPLOY-GAP.md Tier 1.2.)

## 6. Support boundary
You support: the FoldForge images + this documented compose/config. The customer owns:
their host, Docker, Harbor, network/ingress, GPU drivers (on GPU nodes), and their own
object store if they swap MinIO for S3/their store. (Formalize in a SUPPORT.md — see
PRIVATE-DEPLOY-GAP.md Tier 1.3.)

## Not yet (gaps before this is a polished product)
- **License/entitlement:** none yet. Under model B the images live in the customer's
  Harbor beyond your control, so a signed-license-key check in-code is required to gate
  usage/renewal (PRIVATE-DEPLOY-GAP.md Tier 1.1) — build this before charging.
- **Versioned releases:** repos have 0 tags today; CI must build `:vX.Y.Z` images for
  any of the above to be real (Tier 0.2).
- **Real inference:** still GPU-gated; the platform's core value is unproven until one
  real GPU run (STRATEGY §2).
