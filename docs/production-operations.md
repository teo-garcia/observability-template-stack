# Production Operations Profile

This profile is the repository's open-source-first operating baseline for a
small deployment. It turns the local learning stack into a private, durable,
resource-bounded single-node deployment and provides executable SLO and alert
routing checks. It does not claim high availability, a live cloud deployment,
or zero cost.

The local `docker-compose.yml` remains the quickest learning path. The separate
`docker-compose.production.yml` is deliberately reversible and keeps all state
in named volumes.

## Architecture and responsibility boundary

```text
container /metrics ----> Prometheus ----> Alertmanager ----> operator receiver
application OTLP ------> Collector -----> Tempo
container stdout ------> Alloy ----------> Loki
public release URL ----> Blackbox -------> Prometheus
                                            |
                                            +-------------> Grafana
```

The repository owns the signal schema, local storage configuration, dashboards,
SLO rules, bounded defaults, and failure drill. A deployment owner still owns:

- DNS, certificates, ingress, network policy, host patching, and backups;
- real application and static-release targets;
- a tested Alertmanager receiver and its secret delivery mechanism;
- capacity measurements, price review, and the decision to move to object
  storage, managed services, or a highly available topology;
- CDN access logs and edge/cache signals for static releases.

No paid service, cloud credential, remote execution, or hosted control plane is
required by this repository's checks.

## Start and stop

Create a strong password in your shell; do not commit it:

```bash
export GRAFANA_ADMIN_PASSWORD='replace-with-a-secret'
make production-up
```

Grafana, Prometheus, and Alertmanager bind to loopback only:

- Grafana: `http://127.0.0.1:3001`
- Prometheus: `http://127.0.0.1:9090`
- Alertmanager: `http://127.0.0.1:9093`

Application containers send telemetry over the private
`templates-observability` Docker network. The remaining service APIs are not
published on the host.

`make production-down` stops containers and preserves data. The explicitly
destructive `make production-destroy` also deletes this Compose project's named
volumes. Back up or snapshot the volumes before using it on state you need.

For access from another machine, put an authenticated TLS reverse proxy or VPN
in front of Grafana. Do not expose Prometheus, Alertmanager, Loki, Tempo, Alloy,
Blackbox, OTLP, or the Docker socket to the public internet. Grafana login is a
useful final guard, not a replacement for a private network boundary.

Alloy uses the Docker socket to discover container metadata. A read-only mount
does not make that API a low-trust boundary: treat Alloy as a host-trusted
component and run this compact profile on a dedicated host. Before sharing a
host with unrelated workloads, replace direct socket access with a
least-privileged socket proxy or a deployment-native log pipeline and verify
that only the metadata operations required for log discovery are allowed.

## Enrol targets

Container services are discovered from an explicit file rather than from cloud
credentials or provider APIs. Add private `/metrics` endpoints to
`prometheus/file_sd/container-services.yml`:

```yaml
- targets: ["nest-template-monolith:3000"]
  labels:
    service: nest-template-monolith
    profile: container-service
```

Use the canonical service name as both the target's `service` label and the
application's `OTEL_SERVICE_NAME`. Explicitly enable metrics, JSON stdout logs,
and tracing in each deployment because framework defaults differ. Readiness
uses `/health/ready`; liveness uses `/health/live`; neither belongs in the
Prometheus scrape job.

Add public static release URLs to `prometheus/file_sd/static-sites.yml`:

```yaml
- targets: ["https://example.com/"]
  labels:
    service: astro-template-fullstack
    profile: static-web
    module: http_2xx_tls
```

The HTTPS probe records reachability, status, DNS/connect/TLS/request timing,
redirect behavior, and certificate expiry. It cannot observe CDN cache hit
ratio, request volume, client geography, or access events. Forward redacted CDN
access logs to Loki (or another deployment-owned log store) when those signals
are required; do not invent them from probe data.

The checked-in target files are intentionally empty. A missing target is not a
healthy target, and this repository cannot truthfully name a deployment URL on
the consumer's behalf.

## Reliability objectives

| Profile | Availability SLO | Latency SLO | Window |
| --- | --- | --- | --- |
| Container service | 99.5% of HTTP responses are non-5xx | 99.5% complete within 500 ms | rolling 30 days |
| Static web | 99.9% of external probes succeed | 99% complete within 1 second | rolling 30 days |

The objectives are defaults for template learning and small services, not a
contract imposed on every product. Review them against user expectations before
launch. Prometheus evaluates fast multi-window burn (5m and 1h at 14.4x) and
slow availability burn (30m and 6h at 6x). The Production Reliability dashboard
shows the same recording rules, so an alert and its graph cannot silently use
different math.

No-traffic periods produce no container error-budget series and are not counted
as successful requests. `BackendNoTraffic` remains informational. A public
uptime requirement needs an external probe target, not synthetic success from
an idle request counter.

## Bounded defaults

| Signal or process | Bound | Reason |
| --- | --- | --- |
| Prometheus | 30 days and 2 GB; the first limit reached wins | Covers the SLO window while bounding disk |
| Loki | 7-day retention, 2 MB/s sustained and 4 MB burst ingestion | Keeps exact context short-lived and bounded |
| Loki labels | 20 names per series, 5,000 streams per tenant | Limits cardinality and index growth |
| Tempo | 48-hour retention | Keeps recent causality without treating traces as an archive |
| Collector sampling | retain error traces plus a 10% baseline | Preserves failures while bounding normal traffic |
| Trace size/ingestion | 5 MB per trace; 5 MB/s sustained and 10 MB burst | Rejects accidental oversized traces and spikes |
| Alert grouping | 30s group wait, 5m group interval, 4h repeat | Bounds notification volume |
| Containers | 2,400 MiB memory and 3.4 CPU maximum in aggregate | Makes the single-node footprint explicit |

Metrics must use normalized route templates plus service, environment, method,
and status. Logs may carry request and trace IDs, but never user IDs, emails,
tokens, request bodies, or raw URLs as labels. Query strings and secrets must be
redacted before ingestion.

The limits prevent unbounded use; they do not prove the host is large enough.
Measure resident memory, CPU, samples/second, active series, log bytes/second,
spans/second, query latency, and daily volume with representative traffic.

## Cost review

Before a live deployment, record these measured inputs:

| Input | How to estimate |
| --- | --- |
| Compute | host/container hours multiplied by the selected provider rate |
| Persistent storage | provisioned GB-months plus snapshots |
| Network | public ingestion/query/alert egress; private local traffic separately |
| Operations | backup testing, upgrades, incident response, and restore time |

Use the provider's current calculator at review time. This repository does not
hard-code a price because region, architecture, free allowances, and rates
change. The default can run locally without a bill, but any always-on cloud host
and storage may be chargeable.

## SLO response

1. Confirm the alert is still firing in Prometheus and received by
   Alertmanager. Check whether it affects one service or the signal pipeline.
2. For availability, inspect request rate and 5xx by normalized route, then open
   correlated logs and error traces. For latency, compare p50/p95/p99 and find
   the longest child span.
3. Check readiness and dependency timing. Do not restart healthy dependencies
   merely because an application returns 5xx.
4. Stop a risky rollout or restore the last immutable application artifact when
   the regression aligns with a release. Application and schema rollback remain
   owned by that application's deployment contract.
5. Record the incident interval and budget impact. Change an objective only
   through a reviewed policy decision, never to silence an alert.

## Observability stack failure

1. Check Prometheus targets. A component scrape failure can make application
   dashboards incomplete even while the application is healthy.
2. Inspect the failed component's container status and bounded-volume capacity.
3. Restart only that component. Named volumes preserve state across a normal
   Compose restart.
4. If a new configuration caused the failure, restore the previous immutable
   repository revision and restart. Do not delete volumes as a rollback step.
5. If storage is corrupt or exhausted, preserve a copy before repair. Restore
   procedures are deployment-specific and must be tested against real backups.

## Alert delivery

The checked-in `local-noop` receiver proves grouping, inhibition, routing, and
resolution without sending messages or requiring a SaaS account. It is not a
production notification channel. Supply a deployment-owned Alertmanager config
or secret-mounted receiver, then fire a test alert and record receipt before
launch. Never commit webhook URLs, API keys, or SMTP credentials.

## Failure drill and rollback evidence

Run:

```bash
make failure-drill
```

The drill creates an isolated network and volumes, boots the production profile
on alternate loopback ports, stops Tempo, waits for the component-down alert,
proves Alertmanager received it, restores Tempo, proves target recovery and
alert resolution, and removes the isolated resources. Set `KEEP_STACK=1` only
when you need to inspect a failure manually.

This proves the local routing and recovery mechanics. It does not prove a cloud
receiver, backup restore, multi-node failover, CDN logs, or a live application's
SLO. Those remain pre-launch checks for the deployment owner.
