# Distributed tracing deploy runbook (DEBT #M5)

FoldForge threads a **W3C `traceparent`** through the whole request path so one
`trace_id` correlates every log line a request produces:

```
client → gateway → orchestrator → sidecar(s)
         (root /            (persist + re-derive   (bind into structlog
          continue)          per-execution span)    contextvars)
```

This is **already live and verifiable from the logs today** — no extra
infrastructure required. This document covers (a) how to confirm it, and (b) the
*optional* step of shipping those traces to an OpenTelemetry collector for a
waterfall UI (Jaeger/Tempo), which is the only part that needs new infra.

## What's built (no infra needed)

- **gateway** generates a `traceparent` on submit (or continues the caller's if
  they sent one) and forwards it to the orchestrator as gRPC metadata. It logs
  `workflow.submit` with `trace_id`.
- **orchestrator** reads the inbound `traceparent`, **persists the trace-id on the
  workflow row** (`workflows.trace_id`, migration 0006) so it survives the async
  gap between submit and execution — and a crash-recovery reclaim that can move
  execution to a *different* replica. At execution it re-derives a per-execution
  span and injects a `traceparent` into every sidecar `Run` call. Logs
  `workflow.submit` and `claimed workflow` with `trace_id`.
- **sidecars** (af2/boltz/rfdiffusion/proteinmpnn) extract the `traceparent` from
  gRPC metadata and bind the trace-id into structlog contextvars, so every log
  line during that RPC carries it. Each logs one `sidecar.run` line.

No OpenTelemetry SDK is pulled — that crate stack isn't needed just to thread an
id through logs, and `traceparent` is exactly the wire format an OTLP propagator
emits, so the collector step below layers on without changing any service code.

## Verify (GPU-free, log-only)

Submit a workflow with a known `traceparent` and grep the logs:

```bash
TP="00-abcdef0123456789abcdef0123456789-1111111111111111-01"
curl -s -X POST http://localhost:8080/v1/workflows \
  -H "authorization: Bearer $API_TOKEN" \
  -H "content-type: application/json" \
  -H "traceparent: $TP" \
  -d '{"name":"trace-check","steps":[
        {"id":"rf","tool":"rfdiffusion","params":{"contigs":"60-60","num_designs":1}},
        {"id":"mpnn","tool":"proteinmpnn","depends_on":["rf"],"params":{"num_sequences":2}},
        {"id":"af2","tool":"af2","depends_on":["mpnn"],"params":{"num_models":1}}]}'

# The SAME trace-id must appear in every service's logs:
TID=abcdef0123456789abcdef0123456789
docker compose logs gateway      | grep $TID   # workflow.submit
docker compose logs orchestrator | grep $TID   # workflow.submit + claimed workflow
docker compose logs rfdiffusion  | grep $TID   # sidecar.run
docker compose logs proteinmpnn  | grep $TID   # sidecar.run
docker compose logs af2          | grep $TID   # sidecar.run
```

If you DON'T pass a `traceparent`, the gateway mints a fresh root trace-id; it
still threads end to end, you just won't know the id ahead of time (read it from
the `workflow.submit` line, or `SELECT trace_id FROM workflows WHERE id=...`).

## Optional: ship traces to an OTel collector (the infra-gated part)

The logs already carry the correlation id; a collector buys you a span waterfall
(timing per hop) in Jaeger/Tempo. This needs:

1. An OpenTelemetry Collector running (compose overlay provided:
   `docker-compose.trace.yml`), exposing OTLP on `:4317` (gRPC) / `:4318` (HTTP)
   and a Jaeger UI on `:16686`.
2. Each service to **export** spans to the collector. Today the services only
   *log* the trace-id; exporting OTLP spans is a follow-up that requires adding
   the OpenTelemetry SDK to each service (Rust: `opentelemetry` + `opentelemetry-
   otlp` + `tracing-opentelemetry`; Python: `opentelemetry-sdk` +
   `opentelemetry-exporter-otlp`). **These crates/packages are NOT in the offline
   build cache**, so wiring them is deferred to an online build and tracked in
   DEBT. The wire format (`traceparent`) already matches, so no propagation logic
   changes — only the exporter is added.

Bring up the collector overlay alongside the main stack:

```bash
docker compose -f docker-compose.yml -f docker-compose.trace.yml up -d
# Jaeger UI: http://localhost:16686
```

Set `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` on each service once
the SDK exporter is wired.

## Why persist the trace-id (not just span it)

A workflow is submitted, then executed **later** (async, possibly on a different
orchestrator replica after a lease reclaim — see #M1). A trace context held only
in the submit request's memory would be lost across that gap. Storing the
trace-id on the `workflows` row makes the execution-time span re-derivable
wherever and whenever the workflow actually runs, so the trace is continuous even
across a crash-recovery handoff. Nullable column: pre-#M5 rows (and submits with
no `traceparent`) simply start a fresh trace at execution.
