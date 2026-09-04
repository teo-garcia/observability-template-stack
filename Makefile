.PHONY: check compose-check config-check dashboard-check dashboard-generate network up down smoke

COMPOSE_PROJECT_NAME ?= observability-template-stack
SMOKE_PROJECT_NAME ?= observability-template-stack-smoke
export COMPOSE_PROJECT_NAME

PROMETHEUS_IMAGE := prom/prometheus:v3.7.3@sha256:49214755b6153f90a597adcbff0252cc61069f8ab69ce8411285cd4a560e8038
TEMPO_IMAGE := grafana/tempo:3.0.2@sha256:cda87c212d8c584dc0b89e337e7ed648a5100feb657e5d528480ee4fa03dbbe3
LOKI_IMAGE := grafana/loki:3.6.3@sha256:cd6e176883a90c21755f0315688668991634143423f75bdedfef41441b0fdc3c
OTEL_IMAGE := otel/opentelemetry-collector-contrib:0.141.0@sha256:b14234c4bc1b7364629af272e564913bb57bdc9736d45b8b6db5ab3417dc75f9
ALLOY_IMAGE := grafana/alloy:v1.11.0@sha256:e849f170152aff2015427908463a08c48416abade66302cd880379609058042b

check: compose-check config-check dashboard-check

compose-check:
	docker compose config --quiet

config-check:
	docker run --rm --entrypoint /bin/promtool -v "$(CURDIR)/prometheus:/etc/prometheus:ro" $(PROMETHEUS_IMAGE) check config /etc/prometheus/prometheus.yml
	docker run --rm -v "$(CURDIR)/tempo/tempo.yml:/etc/tempo.yml:ro" $(TEMPO_IMAGE) -config.file=/etc/tempo.yml -config.verify=true
	docker run --rm $(LOKI_IMAGE) -config.file=/etc/loki/local-config.yaml -verify-config=true
	docker run --rm -v "$(CURDIR)/otel-collector/config.yml:/etc/otelcol/config.yml:ro" $(OTEL_IMAGE) validate --config=/etc/otelcol/config.yml
	docker run --rm -v "$(CURDIR)/alloy/config.alloy:/etc/alloy/config.alloy:ro" $(ALLOY_IMAGE) validate /etc/alloy/config.alloy

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

up: network
	docker compose up -d

down:
	docker compose down -v --remove-orphans

smoke:
	COMPOSE_PROJECT_NAME=$(SMOKE_PROJECT_NAME) ./scripts/smoke.sh
