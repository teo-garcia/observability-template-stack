.PHONY: check compose-check dashboard-check

check: compose-check dashboard-check

compose-check:
	docker compose config >/tmp/observability-template-stack.compose.yml

dashboard-check:
	find grafana/provisioning/dashboards -name '*.json' -print0 | xargs -0 -n1 jq empty
