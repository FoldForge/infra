# Upgrading a FoldForge on-prem deployment

The orchestrator runs DB migrations on boot, so upgrading the image migrates the
customer's data IN PLACE. On a customer box that's their data — treat every upgrade as
a potentially destructive operation. The golden rule: **back up before you migrate, and
have a tested rollback.**

## Version-skew policy

- One `FOLDFORGE_VERSION` pins all three control-plane services (orchestrator, gateway,
  console) — upgrade them together. Mixed versions are unsupported.
- The orchestrator owns the schema; gateway/console at the same tag are tested against
  it. Never run a gateway/console newer than the orchestrator.
- **patch** (vX.Y.Z → vX.Y.Z+1): no schema change expected; safe rolling restart.
- **minor** (vX.Y → vX.Y+1): may add backward-compatible migrations; back up first.
- **major**: breaking schema; read the release notes — may need a one-way migration +
  a maintenance window. Rollback may require a DB restore, not just an image downgrade.

## Upgrade procedure

```bash
cd deploy/onprem

# 1. BACK UP FIRST (non-negotiable).
./backup.sh                       # → ./backups/<timestamp>

# 2. Deliver the new images into the customer Harbor (vendor side, RELEASE.md §1–2).
#    Then pin the new version:
#    edit .env → FOLDFORGE_VERSION=vX.Y.Z

# 3. Apply. The orchestrator migrates on boot; compose recreates changed services.
docker compose -f docker-compose.onprem.yml up -d

# 4. Verify.
curl -fsS localhost:${GATEWAY_HOST_PORT:-18080}/v1/healthz
docker compose -f docker-compose.onprem.yml logs --tail=50 orchestrator   # migrations OK?
```

A failed migration on boot leaves the orchestrator crash-looping (it won't serve a
half-migrated schema). That's a SAFE failure — the gateway returns errors, but no data
is corrupted. Go to rollback.

## Rollback

```bash
cd deploy/onprem
# (a) image-only rollback — if the migration didn't change schema (patch releases):
#     edit .env → FOLDFORGE_VERSION=<previous>, then:
docker compose -f docker-compose.onprem.yml up -d

# (b) full restore — if a migration changed schema and you must go back:
./restore.sh ./backups/<the-pre-upgrade-timestamp>
#     (restore.sh stops the app, restores DB + artifacts, restarts on the OLD version
#      you set in .env — set FOLDFORGE_VERSION back to the previous tag first.)
```

## Pre-flight checklist (before any customer upgrade)

- [ ] `./backup.sh` ran and `backups/<ts>/postgres.dump` is non-empty.
- [ ] You know the CURRENT version (the rollback target) — it's in the backup MANIFEST.
- [ ] Read the release notes for the target version (schema changes? maintenance window?).
- [ ] A maintenance window is agreed if it's a minor/major (workflows in flight will be
      interrupted by the restart; they resume via lease recovery, but warn the customer).

## Known gap
Migrations are not yet gated by a pre-flight that REFUSES a known-dangerous migration
(PRIVATE-DEPLOY-GAP.md Tier 1.2). Today the safety net is: back up first + the
crash-loop-on-failed-migration behavior (no partial-schema serving) + this runbook.
