# Cutting a release (vendor side)

How a versioned FoldForge release is produced and delivered to an on-prem customer
(delivery model B — customer Harbor). Ties together the CI semver build (Tier 0.2), the
Harbor push (`push-to-harbor.sh`), and the on-prem pin (`FOLDFORGE_VERSION`).

## Versioning

One coordinated version across the deployed services (orchestrator, gateway, console).
They're separate repos but a customer install pins ONE `FOLDFORGE_VERSION`, so cut the
same tag in each at compatible commits. Semver:
- **patch** (v0.1.0 → v0.1.1): bug fixes, no API/schema change.
- **minor** (v0.1 → v0.2): new features, backward-compatible API + DB migration.
- **major**: breaking API/schema — needs an upgrade note (migrations + compat).

The orchestrator owns the DB schema, so its migrations define the version's schema; the
gateway/console must be compatible with the orchestrator at the same tag (CI tests them
against it).

## 1. Tag each deployed repo

For each of orchestrator, gateway, console at the commit you're releasing:
```bash
git tag v0.1.0
git push origin v0.1.0
```
Each repo's CI (on the `v*` tag) builds + pushes `ghcr.io/foldforge/<svc>:v0.1.0` (+
`:0.1`). `latest` is unaffected — it only moves on main pushes. GHCR is the VENDOR build
registry; customers never pull from it (model B).

## 2. Deliver into the customer Harbor

On a host that can reach both GHCR and the customer Harbor:
```bash
docker login ghcr.io
docker login harbor.acme.internal
infra/deploy/onprem/push-to-harbor.sh harbor.acme.internal/foldforge v0.1.0
```
This pulls each `:v0.1.0` from GHCR, re-tags to the customer's Harbor project, pushes.
(If Harbor enforces image scanning, the release must pass their CVE threshold — see
INSTALL.md §4. Track base-image CVEs and rebuild on a clean base before tagging.)

## 3. Issue / refresh the license (if needed)

A new customer or a renewal needs a license key for the term — see LICENSE-OPS.md.
(Unchanged across patch releases; only needed for new customers or expiry renewals.)

## 4. Customer pins the version

In `deploy/onprem/.env`:
```
FOLDFORGE_REGISTRY=harbor.acme.internal/foldforge
FOLDFORGE_VERSION=v0.1.0
```
Then `docker compose -f docker-compose.onprem.yml up -d`. NEVER `latest` on-prem — the
pinned `vX.Y.Z` is what you and support both debug against.

## Upgrades

Deliver the new tag into Harbor (steps 1–2 with the new version), then on the customer
host bump `FOLDFORGE_VERSION` and `up -d`. **Back up Postgres first** — orchestrator runs
migrations on boot (INSTALL.md §5). A backup/restore + migration-rollback runbook is the
next on-prem hardening item (PRIVATE-DEPLOY-GAP.md Tier 1.2).

## GPU sidecars

The control-plane release above does NOT include the GPU sidecar images (large, built
on a GPU box). When delivering GPU nodes, tag + build those too (`build-gpu-sidecar.sh`)
and add them to `push-to-harbor.sh`'s IMAGES list at the same version.

## Status / gaps
- ✅ CI builds versioned images on `v*` tags (orchestrator/gateway/console).
- ⬜ The repos have no tags yet — cut `v0.1.0` only AFTER one real GPU run proves the
  platform works end-to-end (STRATEGY §2). A versioned release of an unproven data plane
  would be a version number on something that's never folded a protein for real.
- ⬜ Coordinated multi-repo tagging is manual today; a release script that tags all three
  at once is a nice-to-have once releases are frequent.
