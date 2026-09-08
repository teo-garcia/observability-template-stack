#!/bin/sh
set -eu

project="${DRILL_PROJECT_NAME:-observability-template-stack-drill}"
network="${DRILL_NETWORK_NAME:-${project}-network}"
prometheus_port="${DRILL_PROMETHEUS_PORT:-19090}"
alertmanager_port="${DRILL_ALERTMANAGER_PORT:-19093}"
grafana_port="${DRILL_GRAFANA_PORT:-13001}"
keep_stack="${KEEP_STACK:-0}"

case "$project:$network" in
  *[!a-zA-Z0-9_.:-]*)
    echo "drill project and network names may contain only letters, digits, dot, underscore, colon, or hyphen" >&2
    exit 1
    ;;
esac

case "$project:$network" in
  *drill*:*drill*) ;;
  *)
    echo "drill project and network names must both contain 'drill'" >&2
    exit 1
    ;;
esac

export OBSERVABILITY_NETWORK="$network"
export PROMETHEUS_PORT="$prometheus_port"
export ALERTMANAGER_PORT="$alertmanager_port"
export GRAFANA_PORT="$grafana_port"
export GRAFANA_ADMIN_PASSWORD="failure-drill-only"

compose() {
  docker compose -p "$project" -f docker-compose.production.yml "$@"
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
    docker network rm "$network" >/dev/null 2>&1 || true
  fi
  exit "$status"
}

wait_http() {
  name=$1
  url=$2
  attempt=0
  until curl -fsS "$url" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 90 ]; then
      echo "$name did not become ready: $url" >&2
      return 1
    fi
    sleep 2
  done
  echo "$name ready"
}

query_value() {
  query=$1
  curl -fsS -G "http://127.0.0.1:${prometheus_port}/api/v1/query" \
    --data-urlencode "query=$query" |
    jq -r '.data.result[0].value[1] // "0"'
}

wait_query_one() {
  description=$1
  query=$2
  attempt=0
  while [ "$(query_value "$query")" != "1" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 90 ]; then
      echo "timed out waiting for $description" >&2
      return 1
    fi
    sleep 2
  done
  echo "$description observed"
}

wait_query_zero() {
  description=$1
  query=$2
  attempt=0
  while [ "$(query_value "$query")" != "0" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 90 ]; then
      echo "timed out waiting for $description" >&2
      return 1
    fi
    sleep 2
  done
  echo "$description observed"
}

trap cleanup EXIT INT TERM

docker network inspect "$network" >/dev/null 2>&1 || docker network create "$network" >/dev/null
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d

wait_http Prometheus "http://127.0.0.1:${prometheus_port}/-/ready"
wait_http Alertmanager "http://127.0.0.1:${alertmanager_port}/-/ready"
wait_http Grafana "http://127.0.0.1:${grafana_port}/api/health"
wait_query_one "healthy Tempo target" 'up{job="tempo"}'

echo "injecting a reversible Tempo outage"
compose stop tempo >/dev/null
wait_query_one \
  "firing component-down alert" \
  'ALERTS{alertname="ObservabilityComponentDown",alertstate="firing",job="tempo"}'

echo "checking Alertmanager routing"
attempt=0
until curl -fsS "http://127.0.0.1:${alertmanager_port}/api/v2/alerts" |
  jq -e 'any(.[]; .labels.alertname == "ObservabilityComponentDown" and .labels.job == "tempo")' >/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 30 ]; then
    echo "Alertmanager did not receive the Tempo alert" >&2
    exit 1
  fi
  sleep 2
done
echo "Alertmanager received the Tempo alert"

echo "restoring Tempo"
compose start tempo >/dev/null
wait_query_one "recovered Tempo target" 'up{job="tempo"}'
wait_query_zero \
  "resolved component-down alert" \
  'ALERTS{alertname="ObservabilityComponentDown",alertstate="firing",job="tempo"}'

echo "production observability failure drill passed"
