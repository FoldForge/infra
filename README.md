# FoldForge `infra`

Infrastructure-as-code for the FoldForge MVP.

- **Terraform** (`terraform/`) provisions Hetzner Cloud (network, firewall, app
  node, Postgres data volume) and Cloudflare R2 (artifact + MSA-cache buckets).
- **Docker Compose** (`compose/`) defines the runtime stack that runs on the app
  node: `postgres`, `orchestrator`, `gateway`, and `caddy` (auto-HTTPS).
- **Scripts** (`scripts/`) bootstrap remote state and deploy the stack.

## Topology (MVP)
```
                 Internet
                    │ 443
              ┌─────▼─────┐
              │   caddy    │  (auto TLS)
              └─────┬─────┘
              ┌─────▼─────┐   gRPC    ┌──────────────┐
              │  gateway   │─────────▶│ orchestrator │
              └───────────┘           └──────┬───────┘
                                  gRPC │     │ sqlx
                       ┌───────────────▼─┐ ┌─▼──────────┐
                       │ GPU sidecars*    │ │ postgres   │
                       │ rfdiff/mpnn/...  │ │ (volume)   │
                       └──────────────────┘ └────────────┘
                       *rented GPU hosts, wired later
   Cloudflare R2: artifact blobs + AF2 MSA cache
```

## Provision
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill tokens + SSH keys
cp backend.hcl.example backend.hcl             # R2 state creds
../scripts/bootstrap-state.sh                  # one-time: create state bucket
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## Deploy the stack
```bash
# on the app node (ssh in), from a checkout of this repo:
cp compose/.env.example compose/.env           # fill secrets + image tags
./scripts/deploy.sh
```

`deploy.sh` pulls pinned images, brings the stack up, and waits on
`/v1/healthz`. Image tags are pinned in `compose/.env` (`GATEWAY_TAG`,
`ORCHESTRATOR_TAG`) — bump them to roll forward.

## Notes
- GPU sidecars are **not** provisioned by Terraform in the MVP; rent GPU hosts
  separately and set `SIDECAR_*` endpoints in `compose/.env`.
- Postgres runs as a container on a Hetzner volume for the MVP. Swap for a
  managed DB by replacing the volume + compose service when scale demands it.

## License
MIT
