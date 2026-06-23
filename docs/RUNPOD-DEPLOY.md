# RunPod GPU sidecar deployment (mode A: GPU on RunPod, control plane on EC2)

RunPod **Pods do not support Docker Compose** (their docs: "Runpod runs Docker for
you, so you cannot ... use Docker Compose on Pods"). So the `docker-compose.gpu.yml`
all-in-one stack does NOT apply here. Instead:

- **Control plane stays on EC2** (already deployed + verified): postgres, orchestrator,
  gateway, console, MinIO. Cheap box, no GPU.
- **RunPod runs the GPU sidecar(s)** — one Pod per model image (our `Dockerfile.gpu`),
  RunPod's native "custom container" model.
- **The orchestrator on EC2 reaches each RunPod sidecar over an SSH tunnel** (the
  sidecar speaks PLAINTEXT gRPC — `add_insecure_port` — so it must NEVER be exposed on
  the public internet; the tunnel is the encryption + the only path in). This matches
  the standing security posture: prefer SSH tunnels, no security-group exposure, no
  plaintext on the wire.

```
  EC2 (control plane)                         RunPod Pod (GPU)
  ┌─────────────────────┐                     ┌──────────────────────┐
  │ orchestrator        │  SSH tunnel (enc)   │ sidecar-af2 :50064   │
  │  SIDECAR_AF2 =      │ ───────────────────▶│  (plaintext gRPC,    │
  │  http://127.0.0.1:  │  localhost:50064 on │   localhost only)    │
  │  50064 (tunnel end) │  EC2 ⇄ :50064 RunPod│  FOLDFORGE_SIDECAR_  │
  │                     │                     │  MOCK=0              │
  └─────────────────────┘                     └──────────────────────┘
```

Start with ONE sidecar (af2 or rfdiffusion) end-to-end before adding the rest.

---

## 0. Prerequisites (you do these — money + credentials)

I do NOT register accounts, attach payment, rent machines, or `docker login` for you.
You:
1. Create a RunPod account + add credit (~$10 covers many test sessions).
2. Build + push the sidecar GPU image to a registry RunPod can pull (GHCR works; the
   image can stay private — give RunPod a read token, same as the EC2 GHCR login).
   Either build on a RunPod Pod (`docker build -f Dockerfile.gpu`) and push, or build
   on any GPU/CUDA box. (First build will iterate on the version pins — see each
   `Dockerfile.gpu`'s STATUS note.)
3. Deploy a Pod from that image (next section) and give me its SSH connection string.

## 1. Deploy the Pod (RunPod console)

- **GPU**: a 24 GB card is enough to prove the pipeline — RTX 4090 / A10 / L4
  (Community Cloud is cheapest). On-Demand, not Spot (Spot can be reclaimed mid-run).
- **Container image**: your pushed `ghcr.io/foldforge/sidecar-<model>:gpu`.
- **Expose TCP port**: the sidecar's gRPC port (af2 `50064`, rfdiffusion `50061`,
  proteinmpnn `50062`, boltz `50063`). RunPod gives a public `proxy.runpod.net` host +
  mapped port, but we will NOT use that for gRPC — we tunnel over SSH instead.
- **Enable SSH**: RunPod exposes SSH (a `root@<pod>.proxy.runpod.net -p <port>` string
  or a direct TCP SSH). Add your public key in RunPod settings.
- **Env**: `FOLDFORGE_SIDECAR_MOCK=0`, `FOLDFORGE_SIDECAR__BIND_ADDR=0.0.0.0:50064`,
  plus the object-store creds (`FOLDFORGE_R2_ENDPOINT` + `AWS_ACCESS_KEY_ID` /
  `AWS_SECRET_ACCESS_KEY`) so artifacts land in the SHARED store the EC2 gateway reads.
  Point R2 at the EC2 MinIO **through a tunnel too** (or a real R2 bucket) — see §3.

## 2. Tunnel: EC2 orchestrator → RunPod sidecar

On the EC2 box, open a tunnel that maps a local port to the sidecar's port inside the
Pod. Plaintext gRPC never leaves the encrypted SSH channel:

```bash
# On EC2. <POD_SSH> is RunPod's SSH target (host + port + key).
# -L: localhost:50064 on EC2  →  127.0.0.1:50064 inside the Pod (the sidecar).
ssh -i runpod_key -N -L 50064:127.0.0.1:50064 root@<pod-host> -p <pod-ssh-port>
```

Keep it alive (autossh, or a systemd unit) so a dropped tunnel reconnects. Then the
orchestrator just talks to `http://127.0.0.1:50064` as if the sidecar were local.

## 3. Object store across the two sides

Sidecars upload artifacts; the gateway downloads them. Both must see the SAME store:
- **Option 1 (simplest): a real R2 bucket.** Point BOTH the RunPod sidecars and the EC2
  gateway/orchestrator at the same Cloudflare R2 endpoint + creds. No tunnel needed for
  storage; R2 is already TLS. (You supply the R2 creds.)
- **Option 2: tunnel MinIO too.** Add `-L 9000:127.0.0.1:9000` from the Pod back to the
  EC2 MinIO (reverse direction: `-R` on the Pod, or `-L` from a process on the Pod).
  More moving parts; R2 is cleaner once you have a bucket.

For a first proof, Option 1 (R2) avoids a second tunnel.

## 4. Point the orchestrator at the tunneled sidecar

On EC2, set the orchestrator's sidecar endpoint to the tunnel's local end and switch
it off mock for that tool. In the EC2 `.env` / compose override:

```
FOLDFORGE_ORCH__RUNNER=            # unset → real GrpcRunner (NOT =mock)
FOLDFORGE_ORCH__SIDECAR_AF2=http://127.0.0.1:50064
# leave the other three pointing at mock sidecars or the same pattern as you add Pods
```

NOTE: today the EC2 orchestrator runs with `RUNNER=mock`. Going real means the OTHER
three tools also need real sidecars (or the DAG fails on the first un-tunneled tool).
For a single-tool proof, submit a workflow with ONLY an af2 step (or whichever sidecar
you brought up), so the DAG never dispatches a tool you haven't deployed.

## 5. Verify (incremental — one sidecar before the DAG)

1. **Tunnel up**: on EC2, `nc -z localhost 50064` succeeds.
2. **Capabilities**: orchestrator log shows the sidecar reporting `*-real` (not mock).
3. **Single-step workflow**: submit a workflow with one step for the deployed tool.
   It should reach SUCCEEDED with a REAL artifact (real sha/size, not the mock's
   fixed-shape synthetic) in the shared store.
4. **Download**: the artifact downloads through the console proxy → gateway → store as
   real model output (the 3D viewer renders a real structure, not synthetic).
5. **Cancel kills GPU** (DEBT #M2): cancel a running workflow; `nvidia-smi` on the Pod
   shows the GPU freed within the grace period.
6. **Cost discipline**: STOP/terminate the Pod when done — RunPod bills by the minute
   until the Pod is stopped. This is the input for real per-GPU-second billing pricing.

## 6. Teardown

`docker stop` is not it — STOP or TERMINATE the Pod in the RunPod console (terminate
to stop billing entirely; stop keeps the volume but may still bill for storage). Kill
the EC2 tunnel (`pkill -f 'ssh.*50064'`). The control plane keeps running on EC2.

## Security recap (matches the standing posture)

- Sidecar gRPC is PLAINTEXT (`add_insecure_port`) → only ever reachable via the SSH
  tunnel; never exposed on a public RunPod TCP port or an open security group.
- Object store is either R2 (TLS) or tunneled MinIO — never plaintext object traffic
  on the public internet.
- RunPod registry pull uses a read-only token you provide; I don't `docker login` for
  you (same boundary as the EC2 GHCR login + not touching gh/R2 creds).
