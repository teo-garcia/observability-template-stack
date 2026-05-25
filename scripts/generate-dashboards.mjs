import { mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const dashboardDir = 'grafana/provisioning/dashboards'

const services = [
  {
    name: 'NestJS',
    service: 'nest-template-monolith',
    uid: 'backend-nest-template-monolith',
    title: 'NestJS Template Observability',
    slug: 'nestjs-template-observability',
    runtime: 'node',
  },
  {
    name: 'AdonisJS',
    service: 'adonis-template-monolith',
    uid: 'backend-adonis-template-monolith',
    title: 'AdonisJS Template Observability',
    slug: 'adonisjs-template-observability',
    runtime: 'node',
  },
  {
    name: 'FastAPI',
    service: 'fastapi-template-monolith',
    uid: 'backend-fastapi-template-monolith',
    title: 'FastAPI Template Observability',
    slug: 'fastapi-template-observability',
    runtime: 'python',
  },
  {
    name: 'Django',
    service: 'django-template-monolith',
    uid: 'backend-django-template-monolith',
    title: 'Django Template Observability',
    slug: 'django-template-observability',
    runtime: 'python',
  },
]

const prom = { type: 'prometheus', uid: 'prometheus' }
const tempo = { type: 'tempo', uid: 'tempo' }
const loki = { type: 'loki', uid: 'loki' }

let panelId = 1

function target(expr, refId = 'A', legendFormat) {
  return {
    refId,
    expr,
    ...(legendFormat ? { legendFormat } : {}),
  }
}

function stat(title, x, y, w, h, expr, options = {}) {
  return {
    id: panelId++,
    type: 'stat',
    title,
    gridPos: { x, y, w, h },
    datasource: prom,
    targets: [target(expr)],
    fieldConfig: {
      defaults: {
        unit: options.unit ?? 'short',
        decimals: options.decimals ?? 2,
        thresholds: options.thresholds
          ? {
              mode: 'absolute',
              steps: options.thresholds,
            }
          : undefined,
      },
      overrides: [],
    },
    options: {
      colorMode: 'value',
      graphMode: options.graphMode ?? 'area',
      justifyMode: 'auto',
      orientation: 'auto',
      reduceOptions: {
        calcs: [options.calc ?? 'lastNotNull'],
        fields: '',
        values: false,
      },
    },
  }
}

function timeseries(title, x, y, w, h, targets, options = {}) {
  return {
    id: panelId++,
    type: 'timeseries',
    title,
    gridPos: { x, y, w, h },
    datasource: prom,
    targets,
    fieldConfig: {
      defaults: {
        unit: options.unit ?? 'short',
        decimals: options.decimals ?? 2,
      },
      overrides: [],
    },
    options: {
      legend: { displayMode: 'table', placement: 'bottom', showLegend: true },
      tooltip: { mode: 'multi', sort: 'desc' },
    },
  }
}

function table(title, x, y, w, h, datasource, targets) {
  return {
    id: panelId++,
    type: 'table',
    title,
    gridPos: { x, y, w, h },
    datasource,
    targets,
    options: {
      showHeader: true,
      cellHeight: 'sm',
    },
  }
}

function logs(title, x, y, w, h, expr) {
  return {
    id: panelId++,
    type: 'logs',
    title,
    gridPos: { x, y, w, h },
    datasource: loki,
    targets: [target(expr)],
    options: {
      showLabels: true,
      showTime: true,
      wrapLogMessage: true,
    },
  }
}

function row(title, y) {
  return {
    id: panelId++,
    type: 'row',
    title,
    gridPos: { x: 0, y, w: 24, h: 1 },
    collapsed: false,
    panels: [],
  }
}

function baseDashboard({ title, uid, tags = [] }) {
  return {
    title,
    uid,
    tags,
    timezone: 'browser',
    schemaVersion: 41,
    version: 1,
    refresh: '10s',
    time: { from: 'now-30m', to: 'now' },
    editable: true,
    graphTooltip: 1,
    panels: [],
  }
}

function serviceDashboard(service) {
  panelId = 1
  const s = service.service
  const dashboard = baseDashboard({
    title: service.title,
    uid: service.uid,
    tags: ['backend', 'template', service.name.toLowerCase(), 'observability'],
  })

  dashboard.panels.push(
    row('Service Health', 0),
    stat('Scrape Health', 0, 1, 4, 4, `up{job="${s}"}`, {
      decimals: 0,
      thresholds: [
        { color: 'red', value: null },
        { color: 'green', value: 1 },
      ],
    }),
    stat('Availability %', 4, 1, 5, 4, `100 * (1 - (sum(rate(http_requests_total{job="${s}",status=~"5.."}[5m])) / clamp_min(sum(rate(http_requests_total{job="${s}"}[5m])), 0.001)))`, {
      unit: 'percent',
      thresholds: [
        { color: 'red', value: null },
        { color: 'orange', value: 95 },
        { color: 'green', value: 99 },
      ],
    }),
    stat('Requests / sec', 9, 1, 5, 4, `sum(rate(http_requests_total{job="${s}"}[5m]))`, {
      unit: 'reqps',
    }),
    stat('5xx %', 14, 1, 5, 4, `100 * backend:http_5xx:ratio5m{job="${s}"}`, {
      unit: 'percent',
      thresholds: [
        { color: 'green', value: null },
        { color: 'orange', value: 1 },
        { color: 'red', value: 5 },
      ],
    }),
    stat('p95 Latency', 19, 1, 5, 4, `max(backend:http_latency:p95_5m{job="${s}"})`, {
      unit: 's',
      thresholds: [
        { color: 'green', value: null },
        { color: 'orange', value: 0.25 },
        { color: 'red', value: 0.5 },
      ],
    }),
    row('Golden Signals', 5),
    timeseries(
      'Traffic and Errors',
      0,
      6,
      12,
      8,
      [
        target(`sum(rate(http_requests_total{job="${s}"}[5m]))`, 'A', 'all requests / sec'),
        target(`sum(rate(http_requests_total{job="${s}",status=~"4.."}[5m]))`, 'B', '4xx / sec'),
        target(`sum(rate(http_requests_total{job="${s}",status=~"5.."}[5m]))`, 'C', '5xx / sec'),
      ],
      { unit: 'reqps' },
    ),
    timeseries(
      'Latency Percentiles',
      12,
      6,
      12,
      8,
      [
        target(`max(backend:http_latency:p50_5m{job="${s}"})`, 'A', 'p50'),
        target(`max(backend:http_latency:p95_5m{job="${s}"})`, 'B', 'p95'),
        target(`max(backend:http_latency:p99_5m{job="${s}"})`, 'C', 'p99'),
      ],
      { unit: 's' },
    ),
    row('Route Breakdown', 14),
    timeseries(
      'Requests by Route and Status',
      0,
      15,
      12,
      8,
      [target(`sum by (method, route, status) (backend:http_requests:rate5m{job="${s}"})`, 'A', '{{method}} {{route}} {{status}}')],
      { unit: 'reqps' },
    ),
    timeseries(
      'p95 Latency by Route',
      12,
      15,
      12,
      8,
      [target(`backend:http_latency:p95_5m{job="${s}"}`, 'A', '{{route}}')],
      { unit: 's' },
    ),
    row('Runtime Resources', 23),
    ...(service.runtime === 'node'
      ? [
          timeseries(
            'CPU Usage',
            0, 24, 12, 8,
            [target(`rate(process_cpu_seconds_total{job="${s}"}[5m])`, 'A', 'CPU rate')],
            { unit: 'percentunit', decimals: 3 },
          ),
          timeseries(
            'Heap Used',
            12, 24, 12, 8,
            [
              target(`nodejs_heap_size_used_bytes{job="${s}"}`, 'A', 'heap used'),
              target(`nodejs_heap_size_total_bytes{job="${s}"}`, 'B', 'heap total'),
            ],
            { unit: 'bytes', decimals: 1 },
          ),
          timeseries(
            'Event Loop Lag',
            0, 32, 12, 8,
            [target(`nodejs_eventloop_lag_seconds{job="${s}"}`, 'A', 'event loop lag')],
            { unit: 's', decimals: 3 },
          ),
          timeseries(
            'GC Duration Rate',
            12, 32, 12, 8,
            [target(`rate(nodejs_gc_duration_seconds_sum{job="${s}"}[5m])`, 'A', '{{kind}}')],
            { unit: 's', decimals: 3 },
          ),
        ]
      : [
          timeseries(
            'CPU Usage',
            0, 24, 12, 8,
            [target(`rate(process_cpu_seconds_total{job="${s}"}[5m])`, 'A', 'CPU rate')],
            { unit: 'percentunit', decimals: 3 },
          ),
          timeseries(
            'Process Memory (RSS)',
            12, 24, 12, 8,
            [target(`process_resident_memory_bytes{job="${s}"}`, 'A', 'RSS')],
            { unit: 'bytes', decimals: 1 },
          ),
          timeseries(
            'GC Collection Rate',
            0, 32, 12, 8,
            [target(`rate(python_gc_collections_total{job="${s}"}[5m])`, 'A', 'gen {{generation}}')],
            { unit: 'ops', decimals: 2 },
          ),
          timeseries(
            'Open File Descriptors',
            12, 32, 12, 8,
            [target(`process_open_fds{job="${s}"}`, 'A', 'open FDs')],
            { unit: 'short', decimals: 0 },
          ),
        ]),
    row('Drilldown', 40),
    table('Recent Traces', 0, 41, 12, 9, tempo, [
      {
        refId: 'A',
        query: `{ resource.service.name = "${s}" }`,
        queryType: 'traceql',
        limit: 20,
      },
    ]),
    logs('Error Logs', 12, 41, 12, 9, `{service_name="${s}"} |~ "(?i)(error|exception|traceback|status[^0-9]*5[0-9][0-9])"`),
    logs('Recent Logs', 0, 50, 24, 8, `{service_name="${s}"}`),
  )

  return dashboard
}

function stackDashboard() {
  panelId = 1
  const dashboard = baseDashboard({
    title: 'Observability Stack Health',
    uid: 'observability-stack-health',
    tags: ['observability', 'platform', 'stack'],
  })

  dashboard.panels.push(
    row('Stack Health', 0),
    stat('Healthy Targets', 0, 1, 6, 4, 'sum(up{job=~"otel-collector|tempo|prometheus|grafana|loki|alloy"})', {
      decimals: 0,
      thresholds: [
        { color: 'red', value: null },
        { color: 'orange', value: 5 },
        { color: 'green', value: 6 },
      ],
    }),
    stat('Prometheus Series', 6, 1, 6, 4, 'prometheus_tsdb_head_series', { decimals: 0 }),
    stat('Loki Write Rate', 12, 1, 6, 4, 'sum(rate(loki_request_duration_seconds_count{route=~".*push.*"}[5m]))', {
      unit: 'reqps',
    }),
    stat('Collector Exported Spans / sec', 18, 1, 6, 4, 'sum(rate(otelcol_exporter_sent_spans[5m]))', {
      unit: 'ops',
    }),
    row('Targets and Scrapes', 5),
    timeseries(
      'Target Health by Job',
      0,
      6,
      12,
      8,
      [target('up{job=~"otel-collector|tempo|prometheus|grafana|loki|alloy|.*-template-monolith"}', 'A', '{{job}}')],
    ),
    timeseries(
      'Scrape Duration by Job',
      12,
      6,
      12,
      8,
      [target('scrape_duration_seconds{job=~"otel-collector|tempo|prometheus|grafana|loki|alloy|.*-template-monolith"}', 'A', '{{job}}')],
      { unit: 's' },
    ),
    row('Signal Pipeline', 14),
    timeseries(
      'Collector Span Export Rate',
      0,
      15,
      8,
      8,
      [target('sum by (exporter) (rate(otelcol_exporter_sent_spans[5m]))', 'A', '{{exporter}}')],
      { unit: 'ops' },
    ),
    timeseries(
      'Tempo Request Rate',
      8,
      15,
      8,
      8,
      [target('sum by (route) (rate(tempo_request_duration_seconds_count[5m]))', 'A', '{{route}}')],
      { unit: 'reqps' },
    ),
    timeseries(
      'Loki Request Rate',
      16,
      15,
      8,
      8,
      [target('sum by (route, status_code) (rate(loki_request_duration_seconds_count[5m]))', 'A', '{{route}} {{status_code}}')],
      { unit: 'reqps' },
    ),
    logs('Stack Logs', 0, 23, 24, 9, '{container=~"templates_(grafana|prometheus|tempo|loki|alloy|otel_collector)"}'),
  )

  return dashboard
}

mkdirSync(dashboardDir, { recursive: true })

for (const service of services) {
  writeFileSync(join(dashboardDir, `${service.service}.json`), `${JSON.stringify(serviceDashboard(service), null, 2)}\n`)
}

writeFileSync(join(dashboardDir, 'observability-stack-health.json'), `${JSON.stringify(stackDashboard(), null, 2)}\n`)
