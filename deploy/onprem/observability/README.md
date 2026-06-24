# Observability pack (Tier 2.1)

FoldForge already emits Prometheus metrics + structured logs; this surfaces them in the
customer's own monitoring. Nothing here runs a monitoring stack for them — it plugs into
theirs (Prometheus/Grafana/Loki/etc.).

## Metrics exposed (verified against source)

Orchestrator (metrics port, default `:9090`):
- `foldforge_workflows_total{state}` — terminal outcomes (SUCCEEDED/FAILED/CANCELLED)
- `foldforge_steps_total{tool,outcome}` — step outcomes per tool
- `foldforge_workflow_duration_seconds` — histogram (claim→terminal)
- `foldforge_steps_in_flight` — gauge of dispatched steps

Gateway (`/metrics` on its HTTP port):
- `foldforge_gateway_http_requests_total{method,path,status}`
- `foldforge_gateway_http_request_duration_seconds` — histogram

## Scrape config (add to the customer's Prometheus)

```yaml
scrape_configs:
  - job_name: foldforge-orchestrator
    static_configs: [{ targets: ['orchestrator:9090'] }]
  - job_name: foldforge-gateway
    metrics_path: /metrics
    static_configs: [{ targets: ['gateway:8080'] }]
```
(Use the addresses reachable from their Prometheus — service names if it's on the same
compose network, else host:port.)

## Alerts

`alerts.yml` — load into Prometheus (`rule_files:`). Rules reference only the metrics
above; thresholds are documented starting points (tune per deployment): gateway/
orchestrator down, 5xx rate, workflow failure ratio, steps-in-flight-stalled (wedged
GPU), p95 latency.

## Dashboard

Build a Grafana dashboard on these queries (kept as queries, not a pinned JSON, so it
matches the customer's Grafana version + datasource UID):
- **Throughput:** `sum(rate(foldforge_workflows_total[5m])) by (state)`
- **Failure ratio:** FAILED / total (see alerts.yml for the exact expr)
- **In-flight:** `foldforge_steps_in_flight`
- **Step outcomes by tool:** `sum(rate(foldforge_steps_total[5m])) by (tool,outcome)`
- **Workflow p50/p95 duration:** `histogram_quantile(0.5|0.95,
  sum(rate(foldforge_workflow_duration_seconds_bucket[10m])) by (le))`
- **Gateway req rate by status:**
  `sum(rate(foldforge_gateway_http_requests_total[5m])) by (status)`
- **Gateway p95 latency:** `histogram_quantile(0.95,
  sum(rate(foldforge_gateway_http_request_duration_seconds_bucket[10m])) by (le))`

## Logs

Both services emit structured JSON logs (tracing-subscriber) to stdout — the customer's
log shipper (Promtail/Fluent Bit/etc.) collects them from Docker. Each carries a
`trace_id` correlating a request across gateway → orchestrator → sidecar (DEBT #M5).
