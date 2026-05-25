# Observability Template Stack

Local Grafana stack for backend-template smoke testing and debugging.

## Services

| Tool | URL | What it stores | Use it when |
| --- | --- | --- | --- |
| Grafana | `http://localhost:3001` | UI over every signal | You want dashboards, traces, logs, and metrics in one place. |
| Prometheus | `http://localhost:9090` | Numeric time series | You need rates, errors, latency, health, and alert rules. |
| Tempo | `http://localhost:3200` | Distributed traces | You need to follow one request through HTTP, DB, Redis, or external calls. |
| Loki | `http://localhost:3100` | Container logs | You need log lines around a service, request, trace, or error. |
| Alloy | `http://localhost:12345` | Log collection pipeline | You need to debug Docker log discovery and Loki shipping. |
| OTel Collector | OTLP HTTP `4318`, gRPC `4317` | Telemetry gateway | Apps send OpenTelemetry spans here before Tempo receives them. |

## Start

```sh
docker network create templates-observability || true
docker compose up -d
```

Run an app template with its observability override, then send traffic:

```sh
cd ../fastapi-template-monolith
docker compose -f docker-compose.yml -f docker-compose.observability.yml up --build
curl http://localhost:8000/health/live
curl http://localhost:8000/
```

The override joins the app container to `templates-observability`, sets a stable
`OTEL_SERVICE_NAME`, and points `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` at the
collector.

## Dashboards

Per-repo dashboards are provisioned at the Grafana root level:

- NestJS: `http://localhost:3001/d/backend-nest-template-monolith/nestjs-template-observability`
- AdonisJS: `http://localhost:3001/d/backend-adonis-template-monolith/adonisjs-template-observability`
- FastAPI: `http://localhost:3001/d/backend-fastapi-template-monolith/fastapi-template-observability`
- Django: `http://localhost:3001/d/backend-django-template-monolith/django-template-observability`

Traces Drilldown is available at:

```text
http://localhost:3001/a/grafana-exploretraces-app/explore
```

Known backend service names:

- `nest-template-monolith`
- `adonis-template-monolith`
- `fastapi-template-monolith`
- `django-template-monolith`

## How To Read The Dashboards

### Scrape Health

`up{job="<service>"}` tells whether Prometheus can scrape the app's `/metrics`
endpoint from inside the Docker network.

- `1`: metrics endpoint is reachable.
- `0`: the app is down, the shared network alias is wrong, the metrics endpoint
  is failing, or the service is not currently running.

Start here when a dashboard is empty. If `up` is `0`, route/error/latency panels
will be stale or empty even if the app works from your browser.

### Requests / Sec

`sum(rate(http_requests_total[5m]))` shows throughput. It answers:

- Is the app receiving traffic?
- Did my smoke test actually hit the service?
- Did traffic stop after a deploy/restart?

Use it first when debugging "nothing is happening".

### 5xx %

This is server error percentage over recent requests. It answers:

- Is the app failing for users?
- Did a route or dependency regression cause server errors?
- Did a restart recover the service?

For local templates, any non-zero 5xx is worth inspecting because traffic volume
is low and usually controlled.

### p95 / Avg Latency

Latency panels use `http_request_duration_seconds`.

- `avg` shows the normal request cost.
- `p95` shows the slow tail and is better for noticing occasional slow DB,
  Redis, or external calls.

If p95 rises but avg stays low, only some requests are slow. Open traces and
look for the slow span. If both rise, the whole route or service is slower.

### Requests By Route

This breaks request rate down by `method`, `route`, and `status`.

Use it to answer:

- Which route is busy?
- Which route is returning 4xx or 5xx?
- Are health checks or metrics scrapes dominating local traffic?

### Recent Traces

Traces show the timeline for individual requests. Open one when:

- latency is high,
- an error appears,
- you need to see DB/Redis/external-call timing,
- you want proof that OpenTelemetry propagation works.

The trace view can jump to logs using the Tempo trace-to-logs link. Backend
request logs emit `trace_id` and `span_id`, so the link filters Loki to the
same service and trace.

### Recent Logs

Logs are labeled with:

- `service_name`
- `container`
- `compose_project`
- `compose_service`

Request logs include:

- `request_id`
- `trace_id`
- `span_id`
- `method`
- `path`
- `status`
- `duration_ms`

Use logs when you need exact events or error messages. Use traces when you need
timing and causality. Use metrics when you need trends.

## Debugging Recipes

### "The dashboard is empty"

1. Check Scrape Health.
2. Open Prometheus targets: `http://localhost:9090/targets`.
3. Confirm the app was started with `docker-compose.observability.yml`.
4. Hit `/health/live`, `/metrics`, and `/` once.
5. Wait one scrape interval, then refresh Grafana.

### "A request is slow"

1. Open the repo dashboard and inspect p95 latency.
2. Open Recent Traces.
3. Pick a trace for the slow route.
4. Find the longest child span.
5. Jump to logs from that trace if you need request context or errors.

### "A route is failing"

1. Check 5xx % and Requests By Route.
2. Identify the `method route status` series.
3. Open Recent Logs for the service.
4. Filter by `status=500` or use the trace-to-logs link from an error trace.

### "Traces Drilldown shows an error"

Grafana Traces Drilldown uses TraceQL metrics like:

```text
{resource.service.name != nil} | rate() by(resource.service.name)
```

Those queries require Tempo's metrics generator and the `local-blocks`
processor. This stack enables both. If Drilldown fails, check:

```sh
docker logs templates_tempo | rg 'empty ring|localblocks|metrics-generator'
```

Then smoke-test TraceQL metrics directly:

```sh
now=$(date +%s)
start=$((now - 1800))
curl -G http://localhost:3200/api/metrics/query_range \
  --data-urlencode 'q={resource.service.name != nil} | rate() by(resource.service.name)' \
  --data-urlencode "start=$start" \
  --data-urlencode "end=$now" \
  --data-urlencode 'step=30s'
```

## Verify

```sh
curl -fsS http://localhost:4318/
curl -fsS http://localhost:9090/-/ready
curl -fsS http://localhost:3200/ready
curl -fsS http://localhost:3001/api/health
curl -fsS http://localhost:3100/ready
curl -fsS http://localhost:12345/-/ready
```

Provisioning smoke:

```sh
curl -fsS 'http://localhost:3001/api/search?query=Observability'
curl -fsS 'http://localhost:3001/api/datasources'
```

Trace smoke:

```sh
curl -G http://localhost:3200/api/search \
  --data-urlencode 'tags=service.name=fastapi-template-monolith'
```

Log smoke:

```sh
curl -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={service_name="fastapi-template-monolith"}'
```
