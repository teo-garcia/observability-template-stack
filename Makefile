.PHONY: check compose-check config-check production-check production-compose-check production-config-check dashboard-check dashboard-generate network production-network up down production-up production-down production-destroy smoke failure-drill

COMPOSE_PROJECT_NAME ?= observability-template-stack
SMOKE_PROJECT_NAME ?= observability-template-stack-smoke
PRODUCTION_PROJECT_NAME ?= observability-template-stack-production
PRODUCTION_COMPOSE := docker compose -p $(PRODUCTION_PROJECT_NAME) -f docker-compose.production.yml
export COMPOSE_PROJECT_NAME

PROMETHEUS_IMAGE := prom/prometheus:v3.7.3@sha256:49214755b6153f90a597adcbff0252cc61069f8ab69ce8411285cd4a560e8038
TEMPO_IMAGE := grafana/tempo:3.0.2@sha256:cda87c212d8c584dc0b89e337e7ed648a5100feb657e5d528480ee4fa03dbbe3
LOKI_IMAGE := grafana/loki:3.6.3@sha256:cd6e176883a90c21755f0315688668991634143423f75bdedfef41441b0fdc3c
OTEL_IMAGE := otel/opentelemetry-collector-contrib:0.141.0@sha256:b14234c4bc1b7364629af272e564913bb57bdc9736d45b8b6db5ab3417dc75f9
ALLOY_IMAGE := grafana/alloy:v1.11.0@sha256:e849f170152aff2015427908463a08c48416abade66302cd880379609058042b
ALERTMANAGER_IMAGE := prom/alertmanager:v0.34.0@sha256:690c7b525f4367aa91f73e2f91c632206d32e97c6384bdbf2fb7a861b420340d
BLACKBOX_IMAGE := prom/blackbox-exporter:v0.28.0@sha256:e753ff9f3fc458d02cca5eddab5a77e1c175eee484a8925ac7d524f04366c2fc

check: compose-check config-check production-check dashboard-check

compose-check:
	docker compose config --quiet

config-check:
	docker run --rm --entrypoint /bin/promtool -v "$(CURDIR)/prometheus:/etc/prometheus:ro" $(PROMETHEUS_IMAGE) check config /etc/prometheus/prometheus.yml
	docker run --rm -v "$(CURDIR)/tempo/tempo.yml:/etc/tempo.yml:ro" $(TEMPO_IMAGE) -config.file=/etc/tempo.yml -config.verify=true
	docker run --rm $(LOKI_IMAGE) -config.file=/etc/loki/local-config.yaml -verify-config=true
	docker run --rm -v "$(CURDIR)/otel-collector/config.yml:/etc/otelcol/config.yml:ro" $(OTEL_IMAGE) validate --config=/etc/otelcol/config.yml
	docker run --rm -v "$(CURDIR)/alloy/config.alloy:/etc/alloy/config.alloy:ro" $(ALLOY_IMAGE) validate /etc/alloy/config.alloy

production-check: production-compose-check production-config-check

production-compose-check:
	GRAFANA_ADMIN_PASSWORD=validation-only $(PRODUCTION_COMPOSE) config --quiet

production-config-check:
	docker run --rm --entrypoint /bin/promtool -v "$(CURDIR)/prometheus:/etc/prometheus:ro" $(PROMETHEUS_IMAGE) check config /etc/prometheus/prometheus.production.yml
	docker run --rm --entrypoint /bin/amtool -v "$(CURDIR)/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" $(ALERTMANAGER_IMAGE) check-config /etc/alertmanager/alertmanager.yml
	docker run --rm -v "$(CURDIR)/blackbox/blackbox.yml:/etc/blackbox/blackbox.yml:ro" $(BLACKBOX_IMAGE) --config.file=/etc/blackbox/blackbox.yml --config.check
	docker run --rm -v "$(CURDIR)/tempo/tempo.production.yml:/etc/tempo.yml:ro" $(TEMPO_IMAGE) -config.file=/etc/tempo.yml -config.verify=true
	docker run --rm -v "$(CURDIR)/loki/loki.production.yml:/etc/loki/loki.yml:ro" $(LOKI_IMAGE) -config.file=/etc/loki/loki.yml -verify-config=true
	docker run --rm -v "$(CURDIR)/otel-collector/config.production.yml:/etc/otelcol/config.yml:ro" $(OTEL_IMAGE) validate --config=/etc/otelcol/config.yml

dashboard-check:
	node --check scripts/generate-dashboards.mjs
	node scripts/generate-dashboards.mjs
	git diff --exit-code -- grafana/provisioning/dashboards
	test -z "$$(git ls-files --others --exclude-standard grafana/provisioning/dashboards)"
	find grafana/provisioning/dashboards -name '*.json' -print0 | xargs -0 -n1 jq empty

dashboard-generate:
	node scripts/generate-dashboards.mjs

network:
	docker network inspect templates-observability >/dev/null 2>&1 || docker network create templates-observability

production-network:
	docker network inspect "$${OBSERVABILITY_NETWORK:-templates-observability}" >/dev/null 2>&1 || docker network create "$${OBSERVABILITY_NETWORK:-templates-observability}"

up: network
	docker compose up -d

down:
	docker compose down -v --remove-orphans

production-up: production-network
	@test -n "$${GRAFANA_ADMIN_PASSWORD:-}" || (echo "GRAFANA_ADMIN_PASSWORD is required" >&2; exit 1)
	$(PRODUCTION_COMPOSE) up -d

production-down:
	GRAFANA_ADMIN_PASSWORD="$${GRAFANA_ADMIN_PASSWORD:-not-used-by-down}" $(PRODUCTION_COMPOSE) down --remove-orphans

production-destroy:
	GRAFANA_ADMIN_PASSWORD="$${GRAFANA_ADMIN_PASSWORD:-not-used-by-destroy}" $(PRODUCTION_COMPOSE) down -v --remove-orphans

smoke:
	COMPOSE_PROJECT_NAME=$(SMOKE_PROJECT_NAME) ./scripts/smoke.sh

failure-drill:
	./scripts/failure-drill.sh
