# License operations (vendor side)

How FoldForge on-prem licenses are issued. Delivery model B (customer Harbor), so the
license is verified OFFLINE by the orchestrator against an embedded Ed25519 PUBLIC key;
the PRIVATE key signs licenses and **never leaves the vendor**.

See the threat model in `orchestrator/src/license.rs`: because customer images can be
unpacked, verification must be asymmetric — a shared secret would let customers forge
licenses. With Ed25519 a customer holding every image still cannot mint a valid license.

## One-time: generate the keypair

Generate a 32-byte seed ONCE from a secure random source and store it offline (password
manager / vault / HSM). This seed is the private key for ALL customer licenses — losing
it or leaking it compromises the whole scheme; rotating it means re-issuing every
license + shipping a new orchestrator build.

```bash
head -c 32 /dev/urandom | xxd -p -c 32      # → your FF_LICENSE_SEED_HEX, store offline
```

Derive + install the public key ONCE:

```bash
cd orchestrator
FF_LICENSE_SEED_HEX=<seed> cargo run --example sign-license -- \
  '{"customer":"_keygen","expires_at":0}'   # prints the PUBLIC KEY hex
```

Paste the printed public key into `orchestrator/src/license.rs`:
```rust
const LICENSE_PUBLIC_KEY_HEX: &str = "<the 64-hex-char public key>";
```
Commit that (the public key is not secret) and cut a release build. Every customer's
orchestrator now verifies against it.

## Per customer: issue a license

```bash
cd orchestrator
FF_LICENSE_SEED_HEX=<seed> cargo run --example sign-license -- \
  '{"customer":"acme-bio","expires_at":1798761600,"license_id":"L-2026-ACME-01","max_workflows":0}'
```
- `expires_at`: unix seconds. Set to the end of the paid term. Renewal = issue a new key
  with a later expiry; the customer swaps `LICENSE_KEY` in `.env` and restarts.
- `license_id`: your reference for support/audit/revocation tracking.
- `max_workflows`: optional cap (0 = unlimited). Enforcement of the cap is a follow-up;
  expiry is enforced today.

Give the printed **LICENSE KEY** to the customer → they set `LICENSE_KEY=` in
`deploy/onprem/.env`.

## Revocation / expiry

There is no online callback (model B is offline by design). Control is via **expiry**:
issue short-ish terms (e.g. annual) so a non-renewing customer's license lapses on its
own. On lapse the orchestrator refuses to start the executor/server (no new workflows)
but does NOT touch their data. There is no kill-switch for an already-issued,
unexpired key — that's the intended trade-off for offline verification; keep terms
bounded if that matters.

## Private-key discipline (do not skip)

- The seed (private key) lives ONLY offline + wherever you run `sign-license`. NEVER in
  this repo, any image, any CI secret that ends up in a shipped artifact.
- `sign-license` is in `orchestrator/examples/` precisely so it is NOT linked into the
  release binary — the customer's orchestrator can verify but can never sign.
- If the seed leaks: rotate (new keypair), update `LICENSE_PUBLIC_KEY_HEX`, ship a new
  orchestrator version, re-issue all customer licenses. Painful — protect the seed.
