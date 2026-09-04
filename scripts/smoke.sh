#!/bin/sh
set -eu

project="${COMPOSE_PROJECT_NAME:-observability-template-stack-smoke}"
keep_stack="${KEEP_STACK:-0}"

compose() {
  docker compose -p "$project" "$@"
}

cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ "$status" -ne 0 ]; then
    compose ps -a || true
    compose logs --no-color --tail=100 || true
  fi
  if [ "$keep_stack" != "1" ]; then
    compose down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  exit "$status"
}

wait_for() {
  name=$1
  url=$2
  attempt=0
  until curl -fsS "$url" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 60 ]; then
      echo "$name did not become ready: $url" >&2
      return 1
    fi
    sleep 2
  done
  echo "$name ready"
}

trap cleanup EXIT INT TERM

docker network inspect templates-observability >/dev/null 2>&1 || \
  docker network create templates-observability >/dev/null

compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d

wait_for Prometheus http://localhost:9090/-/ready
wait_for Tempo http://localhost:3200/ready
wait_for Grafana http://localhost:3001/api/health
wait_for Loki http://localhost:3100/ready
wait_for Alloy http://localhost:12345/-/ready
wait_for "OTel Collector" http://localhost:8889/metrics

echo "checking Grafana dashboards"
curl -fsS http://localhost:3001/api/search |
  jq -e 'map(select(.type == "dash-db")) | length == 7' >/dev/null
echo "checking Grafana datasources"
curl -fsS http://localhost:3001/api/datasources |
  jq -e 'map(.uid) | sort == ["loki", "prometheus", "tempo"]' >/dev/null
echo "checking Prometheus rules"
curl -fsS http://localhost:9090/api/v1/rules |
  jq -e '.status == "success" and (.data.groups | length > 0)' >/dev/null

echo "checking Tempo TraceQL metrics"
now=$(date +%s)
start=$((now - 300))
curl -fsS -G http://localhost:3200/api/metrics/query_range \
  --data-urlencode 'q={resource.service.name != nil} | rate() by(resource.service.name)' \
  --data-urlencode "start=$start" \
  --data-urlencode "end=$now" \
  --data-urlencode 'step=30s' |
  jq -e '(.series | type == "array") and (.metrics.completedJobs == .metrics.totalJobs)' >/dev/null

if compose ps -a --status exited --quiet | grep -q .; then
  echo "one or more stack containers exited" >&2
  exit 1
fi

echo "observability stack smoke passed"
