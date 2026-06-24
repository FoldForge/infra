# FoldForge on-prem support boundary

What the vendor supports vs what the customer owns. This exists so a "private
deployment" engagement doesn't silently become unbounded consulting on the customer's
infrastructure — every k8s/driver/network issue is NOT a FoldForge bug.

## What the vendor supports

- The FoldForge application images (orchestrator, gateway, console, GPU sidecars) at a
  released `vX.Y.Z`, running the documented `docker-compose.onprem.yml` configuration.
- Bugs in FoldForge behavior reproducible on a supported, documented config.
- The documented install / upgrade / backup / restore procedures (INSTALL/UPGRADE.md).
- Schema migrations shipped with a release and the upgrade path between adjacent
  released versions.
- License issuance + renewal (LICENSE-OPS.md).

## What the customer owns (not vendor support)

- **Their host + OS + Docker / container runtime** — provisioning, patching, disk, the
  Docker daemon itself.
- **Their Harbor registry** — availability, the CA/TLS trust, image scanning policy.
- **GPU nodes** — NVIDIA drivers, CUDA, the NVIDIA Container Toolkit, GPU availability;
  FoldForge runs ON the GPU but does not manage the driver stack.
- **Network / ingress / VPN / firewall** — reaching the gateway/console, the SSH tunnels
  to GPU nodes, DNS, TLS termination in front of the stack.
- **Their object store** if they swap the bundled MinIO for S3/their store — its
  availability, credentials, lifecycle.
- **Model weights** — licensing + download/staging of RFdiffusion/AF2/etc. weights
  (these are third-party, not FoldForge's to redistribute).
- **Their own modifications** — any change to the compose, images, or config beyond the
  documented knobs voids support for the affected area until reproduced on a clean config.

## Support tiers (template — set per contract)

| Tier | Scope | Response |
|------|-------|----------|
| Sev-1 | Production down on a supported config | best-effort, fastest |
| Sev-2 | Degraded / workaround exists | next business day |
| Sev-3 | Question / minor / cosmetic | scheduled |
| Out of scope | Customer-infra issues (above) | advisory only / billable consulting |

(Concrete SLAs are a commercial decision per customer — this table is the shape, not a
commitment.)

## What we need from the customer to support an issue

- The `FOLDFORGE_VERSION` (from `.env` / backup MANIFEST).
- Orchestrator + gateway logs around the issue (`docker compose ... logs`).
- Whether the config is the documented one (any deviations).
- For GPU issues: `nvidia-smi` output + the sidecar logs (to separate a FoldForge bug
  from a driver/toolkit problem — the boundary above).

## The honest framing

This boundary is what makes private deployment a *product* sale rather than an
open-ended consulting retainer. Customer-infrastructure problems get advisory help, but
they're the customer's to fix or a separately-billed engagement — not bundled support.
