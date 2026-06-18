# Deploying the control plane to a shared host (e.g. AWS EC2)

This is the path for putting FoldForge's **control plane** (postgres + orchestrator +
gateway) on a Linux box that already runs other things — as opposed to
`terraform/` + `docker-compose.yml`, which provision and own a dedicated Hetzner node.

It runs the **GPU-free mock runner**, so the API comes up and workflows execute
end-to-end with **no GPU and no object store**. This proves the control plane on the
host; real inference needs GPU sidecars (see `../foldforge/docs/STRATEGY.md` §2).

## What it deliberately avoids on a shared host
- **No caddy** — 80/443 are usually already taken. The gateway is published on a high
  port (`GATEWAY_HOST_PORT`, default `18080`).
- **postgres has no host port** — reachable only as `postgres:5432` on the compose
  network, so it can't collide with another postgres on the host's 5432.
- **No registry pull** — images are built from sibling repos, so no GHCR creds.

## Prerequisites on the host
- Docker with the compose plugin. On this kind of box compose is often available
  under root: test with `sudo docker compose version`.
- The two Rust repos must be cloned **with submodules** (they vendor `proto`):
  ```bash
  cd /root/git
  git clone --recurse-submodules <orchestrator-url> foldforge-orchestrator
  git clone --recurse-submodules <gateway-url>      foldforge-gateway
  git clone                      <infra-url>        foldforge-infra
  ```
  If you cloned without submodules: `git -C foldforge-orchestrator submodule update --init --recursive` (same for gateway).

## Bring it up
```bash
cd /root/git/foldforge-infra/compose
cp ec2.env.example .env
#   edit .env: set POSTGRES_PASSWORD and API_TOKEN (any secret values)
sudo docker compose -f docker-compose.ec2.yml --env-file .env up -d --build
```
First build compiles two Rust services — a few minutes. Then verify **on the host**
(no security-group change needed for a local check):
```bash
PORT=$(grep -E '^GATEWAY_HOST_PORT=' .env | cut -d= -f2); PORT=${PORT:-18080}
curl -s localhost:$PORT/v1/healthz            # -> ok
curl -s localhost:$PORT/v1/readyz             # -> {"status":"ready",...} once DB is up
T=$(grep -E '^API_TOKEN=' .env | cut -d= -f2)
curl -s -H "Authorization: Bearer $T" localhost:$PORT/v1/workflows   # -> JSON list
```

## Exposing it (optional)
Only if you want it reachable off-box: open `GATEWAY_HOST_PORT` in the EC2 security
group, and ideally put TLS in front (reuse the host's existing caddy as a reverse
proxy, or an AWS ALB). Until then it's host-local only.

## Operating
```bash
sudo docker compose -f docker-compose.ec2.yml --env-file .env ps        # status
sudo docker compose -f docker-compose.ec2.yml --env-file .env logs -f gateway
sudo docker compose -f docker-compose.ec2.yml --env-file .env down      # stop (keeps the pg volume)
sudo docker compose -f docker-compose.ec2.yml --env-file .env up -d --build  # redeploy after a git pull
```
The postgres data lives in the named volume `foldforge_pg` and survives `down`.

## Going beyond mock
To run real inference later: set `FOLDFORGE_ORCH__RUNNER` back to the real runner,
add the four `FOLDFORGE_ORCH__SIDECAR_*` endpoints (GPU hosts), and give the gateway
R2/S3 creds for artifact downloads. That's the GPU milestone, not this one.
