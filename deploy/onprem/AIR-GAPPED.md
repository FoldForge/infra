# Air-gapped / offline model weights (Tier 2.5)

The GPU sidecars download model weights + reference data from the internet on first run.
A customer site with no outbound internet (or a Harbor-only egress policy) must
PRE-STAGE these. Per model, because each gets its weights differently:

| Sidecar | Weights source | Air-gapped staging |
|---------|----------------|--------------------|
| **proteinmpnn** | Bundled in the cloned repo (`vanilla_model_weights/`, `soluble_model_weights/`) | Already in the image — nothing extra. |
| **rfdiffusion** | Separate download into `models/` (not in the repo) | Download on a connected box, bake into the image or mount a volume at the models path. Largest manual step. |
| **boltz** | Weights + Chemical Component Dictionary download to the Boltz cache on first `boltz predict` | Pre-run once on a connected box, capture the cache dir, mount it (or bake it) on the air-gapped node. |
| **af2** | ColabFold downloads params on first run; MSA normally hits a remote MSA server | Pre-stage the params into the ColabFold cache; for MSA, EITHER pre-compute MSAs and pass them via the request (the af2 sidecar's first-class MSA cache) OR run a local MSA server — a remote MSA server is NOT reachable air-gapped. |

## General pattern

1. On a CONNECTED GPU box, run each sidecar once (or its model's download step) so the
   weights/cache populate.
2. Capture the populated cache/weights directory (`docker cp` out of the container, or a
   mounted volume).
3. Deliver it to the customer (same channel as images — into their environment).
4. On the air-gapped node, either:
   - **bake** the weights into a derived image (`FROM ghcr.io/foldforge/sidecar-X:vN` +
     `COPY weights/`), pushed to their Harbor; or
   - **mount** a volume at the model's weight/cache path at run time.

## The MSA caveat (af2 / boltz)

AF2 and Boltz need a multiple-sequence alignment for protein chains. By default they
call a remote MSA server — **impossible air-gapped**. Options:
- Pre-compute MSAs on a connected box and pass them through the request (af2's MSA cache
  is a first-class API surface — see sidecar-af2/docs/GPU-DEPLOY.md).
- Run a local MSA pipeline (e.g. a local colabfold_search + sequence DBs) inside the
  customer environment — large reference DBs, a separate staging task.
Document which the customer needs based on their workloads; pure structure prediction
from a supplied MSA needs neither.

## Status
This is documentation of the staging procedure, not an automated bundler. An "offline
weights bundle" build step (produce a versioned weights tarball per model alongside the
image release) is the natural follow-up once a real air-gapped customer is in scope —
don't build the automation before there's a customer who needs it.
