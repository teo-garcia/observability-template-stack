<div align="center">

# Observability Template Stack

**Local Grafana observability stack for backend templates with metrics, logs,
traces, dashboards, alerts, and trace-to-log correlation**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Grafana](https://img.shields.io/badge/Grafana-12.3-F46800?logo=grafana&logoColor=white)](https://grafana.com)
[![Prometheus](https://img.shields.io/badge/Prometheus-3.7-E6522C?logo=prometheus&logoColor=white)](https://prometheus.io)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-Collector-000000?logo=opentelemetry&logoColor=white)](https://opentelemetry.io)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docker.com)

Part of the [@teo-garcia/templates](https://github.com/teo-garcia/templates)
ecosystem

</div>

---

## Features

| Category | Technologies |
| --- | --- |
| **Dashboards** | Grafana with provisioned datasources and per-backend dashboards |
| **Metrics** | Prometheus scraping app `/metrics` endpoints and stack health |
| **Traces** | Tempo with TraceQL metrics support for Traces Drilldown |
| **Logs** | Loki with Alloy Docker log discovery and service labels |
| **Collection** | OpenTelemetry Collector as the shared OTLP gateway |
| **Correlation** | Tempo trace-to-logs links using exact `trace_id` matches |
| **Alerts** | Prometheus examples for target-down, 5xx rate, and p95 latency |
| **DevOps** | Docker Compose stack on the shared `templates-observability` network |

---

## Requirements

- Docker and Docker Compose
- Active backend template repo with `docker-compose.observability.yml`
- Shared Docker network named `templates-observability`
- One of the active backend monolith templates:
  `nest-template-monolith`, `adonis-template-monolith`,
  `fastapi-template-monolith`, or `django-template-monolith`

---

## Quick Start

```bash
docker network create templates-observability || true
docker compose up -d
```

Run an app template with its observability override, then send traffic:

```bash
cd ../fastapi-template-monolith
docker compose -f docker-compose.yml -f docker-compose.observability.yml up --build
curl http://localhost:8000/health/live
curl http://localhost:8000/
```

Grafana starts on `http://localhost:3001`. Anonymous admin access is enabled for
local template practice only.

---

## Services

| Tool | URL | Role |
| --- | --- | --- |
| Grafana | `http://localhost:3001` | Dashboards, Explore, logs, traces, and metrics UI |
| Prometheus | `http://localhost:9090` | Metrics storage, queries, targets, and alert rules |
| Tempo | `http://localhost:3200` | Distributed traces and TraceQL metrics |
| Loki | `http://localhost:3100` | Container logs from backend templates |
| Alloy | `http://localhost:12345` | Docker log discovery and Loki shipping |
| OTel Collector | `4317`, `4318`, `8889` | Shared OTLP gateway for backend traces |

---

## Dashboards

| Template | Dashboard |
| --- | --- |
| NestJS | `http://localhost:3001/d/backend-nest-template-monolith/nestjs-template-observability` |
| AdonisJS | `http://localhost:3001/d/backend-adonis-template-monolith/adonisjs-template-observability` |
| FastAPI | `http://localhost:3001/d/backend-fastapi-template-monolith/fastapi-template-observability` |
| Django | `http://localhost:3001/d/backend-django-template-monolith/django-template-observability` |

Traces Drilldown is available at:

```text
http://localhost:3001/a/grafana-exploretraces-app/explore
```

Known backend service names:

- `nest-template-monolith`
- `adonis-template-monolith`
- `fastapi-template-monolith`
- `django-template-monolith`

---

## How To Use The Signals

| Signal | Use it when | Start with |
| --- | --- | --- |
| Metrics | You need rates, error percentages, latency, or target health | Repo dashboard, then Prometheus targets |
| Logs | You need exact request events, exception text, or request context | Recent Logs panel or Loki Explore |
| Traces | You need request timing, slow spans, DB/Redis/external-call cost, or causality | Recent Traces panel or Traces Drilldown |

Request logs include `request_id`, `trace_id`, `span_id`, `method`, `path`,
`status`, and `duration_ms`. Traces can jump to matching Loki logs through the
Tempo trace-to-logs link.

---

## Dashboard Concepts

### Scrape Health

`up{job="<service>"}` tells whether Prometheus can scrape the app's `/metrics`
endpoint from inside the Docker network.

- `1`: metrics endpoint is reachable.
- `0`: the app is down, the shared network alias is wrong, the metrics endpoint
  is failing, or the service is not currently running.

Start here when a dashboard is empty. If `up` is `0`, route/error/latency panels
will be stale or empty even if the app works from your browser.

### Requests / Sec

`sum(rate(http_requests_total[5m]))` shows throughput. It answers whether the
app is receiving traffic, whether a smoke test hit the service, and whether
traffic stopped after a restart.

### 5xx %

This is server error percentage over recent requests. For local templates, any
non-zero 5xx is worth inspecting because traffic volume is low and controlled.

### p95 / Avg Latency

Latency panels use `http_request_duration_seconds`.

- `avg` shows the normal request cost.
- `p95` shows the slow tail and is better for occasional slow DB, Redis, or
  external calls.

If p95 rises but avg stays low, only some requests are slow. Open traces and
look for the slow span. If both rise, the whole route or service is slower.

### Requests By Route

This breaks request rate down by `method`, `route`, and `status`. Use it to see
which route is busy, which route is failing, and whether health checks or
metrics scrapes dominate local traffic.

---

## Debugging Recipes

| Symptom | Checks |
| --- | --- |
| Dashboard is empty | Check Scrape Health, Prometheus targets, the app observability override, then hit `/health/live`, `/metrics`, and `/`. |
| Request is slow | Inspect p95 latency, open a recent trace for the route, find the longest child span, then jump to logs if needed. |
| Route is failing | Check 5xx % and Requests By Route, identify the route/status series, then filter logs or use trace-to-logs. |
| Traces Drilldown errors | Check Tempo logs for `empty ring`, `localblocks`, or `metrics-generator`, then smoke-test TraceQL metrics. |

TraceQL metrics smoke:

```bash
now=$(date +%s)
start=$((now - 1800))
curl -G http://localhost:3200/api/metrics/query_range \
  --data-urlencode 'q={resource.service.name != nil} | rate() by(resource.service.name)' \
  --data-urlencode "start=$start" \
  --data-urlencode "end=$now" \
  --data-urlencode 'step=30s'
```

---

## Verification

| Command | Description |
| --- | --- |
| `docker compose config` | Validate Compose configuration |
| `curl -fsS http://localhost:9090/-/ready` | Check Prometheus readiness |
| `curl -fsS http://localhost:3200/ready` | Check Tempo readiness |
| `curl -fsS http://localhost:3001/api/health` | Check Grafana health |
| `curl -fsS http://localhost:3100/ready` | Check Loki readiness |
| `curl -fsS http://localhost:12345/-/ready` | Check Alloy readiness |

Provisioning smoke:

```bash
curl -fsS 'http://localhost:3001/api/search?query=Observability'
curl -fsS 'http://localhost:3001/api/datasources'
```

Trace smoke:

```bash
curl -G http://localhost:3200/api/search \
  --data-urlencode 'tags=service.name=fastapi-template-monolith'
```

Log smoke:

```bash
curl -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={service_name="fastapi-template-monolith"}'
```

---

## Project Structure

| Path | Purpose |
| --- | --- |
| `docker-compose.yml` | Local Grafana, Prometheus, Tempo, Loki, Alloy, and OTel Collector stack |
| `grafana/provisioning/datasources/` | Provisioned Prometheus, Tempo, and Loki datasources |
| `grafana/provisioning/dashboards/` | Provisioned per-backend Grafana dashboards |
| `prometheus/` | Scrape config and backend alert examples |
| `tempo/` | Tempo config with metrics generator and local blocks enabled |
| `otel-collector/` | OTLP receiver and Tempo exporter pipeline |
| `alloy/` | Docker log discovery and Loki forwarding config |

---

## Shared Governance

| Area | Tooling |
| --- | --- |
| Local metrics | Prometheus scrape targets for active backend monoliths |
| Local traces | OpenTelemetry Collector plus Tempo |
| Local logs | Alloy Docker discovery plus Loki |
| Dashboards | Grafana file provisioning at the root folder |
| Alerts | Prometheus rule examples for common backend symptoms |
| Network | Shared `templates-observability` Docker network |

---

## Related Templates

| Template | Description |
| --- | --- |
| `nest-template-monolith` | NestJS backend with OpenTelemetry SDK wiring |
| `adonis-template-monolith` | AdonisJS backend with OpenTelemetry SDK wiring |
| `fastapi-template-monolith` | FastAPI backend with OpenTelemetry SDK wiring |
| `django-template-monolith` | Django backend with OpenTelemetry SDK wiring |

---

## License

MIT

---

<div align="center">
  <sub>Built by <a href="https://github.com/teo-garcia">teo-garcia</a></sub>
</div>
