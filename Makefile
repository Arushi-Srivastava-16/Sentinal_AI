.PHONY: dev-up dev-down dev-logs dev-ps \
        stack-up stack-down stack-logs \
        install install-dev lint format typecheck \
        test test-unit test-integration test-e2e \
        load-test \
        demo-a demo-b demo-c \
        neo4j-browser logs-gateway \
        k8s-apply k8s-delete k8s-status \
        seed-neo4j clean help

# =============================================================================
# Sentinel — Developer Workflow
# =============================================================================

DOCKER_COMPOSE_DEV=docker-compose -f docker-compose.dev.yml
DOCKER_COMPOSE=docker-compose -f docker-compose.yml

# Colours
CYAN  := \033[0;36m
RESET := \033[0m

help:
	@echo ""
	@echo "$(CYAN)Sentinel — available targets$(RESET)"
	@echo ""
	@echo "  Infrastructure"
	@echo "    dev-up          Start Neo4j, Redis, Ollama (infra only)"
	@echo "    dev-down        Stop and remove infra containers"
	@echo "    dev-logs        Tail logs from all infra containers"
	@echo "    dev-ps          Show running container status"
	@echo "    dev-health      Check all infra services are healthy"
	@echo ""
	@echo "  Development"
	@echo "    install         Install Python dependencies (venv)"
	@echo "    install-dev     Install Python + dev dependencies"
	@echo "    install-ui      Install dashboard Node dependencies"
	@echo "    run-gateway     Run gateway with hot reload"
	@echo "    run-worker      Run Redis Streams → Neo4j audit worker"
	@echo "    run-dashboard   Run dashboard in dev mode (Vite HMR)"
	@echo ""
	@echo "  Code Quality"
	@echo "    lint            Run ruff linter"
	@echo "    format          Run ruff formatter"
	@echo "    typecheck       Run mypy in strict mode"
	@echo ""
	@echo "  Testing"
	@echo "    test            Run all tests"
	@echo "    test-unit       Unit tests only (no infra required)"
	@echo "    test-integration Integration tests (requires dev-up)"
	@echo "    test-e2e        End-to-end demo scenarios (requires full stack)"
	@echo ""
	@echo "  Demo"
	@echo "    demo-a          Run Scenario A: Rogue Exfiltrator"
	@echo "    demo-b          Run Scenario B: Rate Limit Abuser"
	@echo "    demo-c          Run Scenario C: Policy Version Rollback"
	@echo ""
	@echo "  Full stack (all services incl. gateway + dashboard)"
	@echo "    stack-up        Start full docker-compose stack"
	@echo "    stack-down      Stop full stack"
	@echo "    stack-logs      Tail all service logs"
	@echo ""
	@echo "  Load Testing"
	@echo "    load-test       Run Locust load test (headless, 500 users, 10m)"
	@echo "    load-test-ui    Run Locust with web UI at http://localhost:8089"
	@echo ""
	@echo "  Observability"
	@echo "    logs-gateway    Tail gateway container logs (structured JSON)"
	@echo "    neo4j-browser   Open Neo4j browser in default browser"
	@echo "    grafana         Open Grafana in default browser"
	@echo "    prometheus      Open Prometheus in default browser"
	@echo ""
	@echo "  Kubernetes"
	@echo "    k8s-apply       Apply base manifests to current kubectl context"
	@echo "    k8s-delete      Delete sentinel namespace"
	@echo "    k8s-status      Show pod/hpa/ingress status in sentinel namespace"
	@echo ""
	@echo "  Utilities"
	@echo "    seed-neo4j      Populate Neo4j with sample data"
	@echo "    clean           Remove __pycache__, .mypy_cache, build artefacts"
	@echo ""

# =============================================================================
# Infrastructure
# =============================================================================

dev-up:
	@echo "$(CYAN)Starting infra (Neo4j, Redis, Ollama)...$(RESET)"
	$(DOCKER_COMPOSE_DEV) up -d
	@echo "$(CYAN)Waiting for services to be healthy...$(RESET)"
	@$(MAKE) dev-health

dev-down:
	$(DOCKER_COMPOSE_DEV) down

dev-logs:
	$(DOCKER_COMPOSE_DEV) logs -f

dev-ps:
	$(DOCKER_COMPOSE_DEV) ps

dev-health:
	@echo "Checking Redis..."
	@until docker exec sentinel-redis redis-cli ping 2>/dev/null | grep -q PONG; do \
		echo "  Redis not ready, retrying..."; sleep 2; done
	@echo "  Redis OK"
	@echo "Checking Neo4j..."
	@until docker exec sentinel-neo4j cypher-shell -u neo4j -p sentinel_dev_password "RETURN 1" 2>/dev/null | grep -q 1; do \
		echo "  Neo4j not ready, retrying..."; sleep 3; done
	@echo "  Neo4j OK"
	@echo "Checking Ollama..."
	@until curl -sf http://localhost:11434/api/tags > /dev/null; do \
		echo "  Ollama not ready, retrying..."; sleep 2; done
	@echo "  Ollama OK"
	@echo "$(CYAN)All services healthy$(RESET)"

# =============================================================================
# Development
# =============================================================================

install:
	python3.12 -m venv .venv
	.venv/bin/pip install --upgrade pip
	.venv/bin/pip install -r gateway/requirements.txt
	.venv/bin/pip install -r judge/requirements.txt

install-dev: install
	.venv/bin/pip install -r requirements-dev.txt

install-ui:
	cd dashboard && npm ci

run-gateway:
	.venv/bin/uvicorn gateway.main:app --reload --host 0.0.0.0 --port 8000

run-worker:
	.venv/bin/python -m database.stream_consumer

run-dashboard:
	cd dashboard && npm run dev

# =============================================================================
# Code Quality
# =============================================================================

lint:
	.venv/bin/ruff check gateway/ judge/ database/ shared/ policies/ sentinel-sdk/ agents/

format:
	.venv/bin/ruff format gateway/ judge/ database/ shared/ policies/ sentinel-sdk/ agents/
	.venv/bin/ruff check --fix gateway/ judge/ database/ shared/ policies/ sentinel-sdk/ agents/

typecheck:
	.venv/bin/mypy gateway/ judge/ database/ shared/ policies/ sentinel-sdk/ --strict

# =============================================================================
# Testing
# =============================================================================

test: test-unit test-integration

test-unit:
	.venv/bin/pytest tests/unit/ -v --tb=short

test-integration:
	.venv/bin/pytest tests/integration/ -v --tb=short

test-e2e:
	.venv/bin/pytest tests/e2e/ -v --tb=short -s

# =============================================================================
# Full stack
# =============================================================================

stack-up:
	@echo "$(CYAN)Starting full Sentinel stack...$(RESET)"
	$(DOCKER_COMPOSE) up -d
	@echo "$(CYAN)Waiting for gateway to be healthy...$(RESET)"
	@until curl -sf http://localhost:8000/health > /dev/null; do \
		echo "  Gateway not ready, retrying..."; sleep 3; done
	@echo "$(CYAN)All services healthy. Dashboard: http://localhost:3000$(RESET)"

stack-down:
	$(DOCKER_COMPOSE) down

stack-logs:
	$(DOCKER_COMPOSE) logs -f

# =============================================================================
# Load Testing
# =============================================================================

LOAD_USERS     ?= 500
LOAD_SPAWN     ?= 50
LOAD_DURATION  ?= 10m
LOAD_HOST      ?= http://localhost:8000
LOAD_RESULTS   := tests/load/results

load-test:
	@mkdir -p $(LOAD_RESULTS)
	.venv/bin/locust \
		-f tests/load/locustfile.py \
		--headless \
		-u $(LOAD_USERS) -r $(LOAD_SPAWN) \
		-t $(LOAD_DURATION) \
		--host $(LOAD_HOST) \
		--csv $(LOAD_RESULTS)/run_$(shell date +%s) \
		--html $(LOAD_RESULTS)/report_$(shell date +%s).html
	@echo "$(CYAN)Load test complete. Results in $(LOAD_RESULTS)/$(RESET)"

load-test-ui:
	.venv/bin/locust \
		-f tests/load/locustfile.py \
		--host $(LOAD_HOST)
	@echo "$(CYAN)Locust UI at http://localhost:8089$(RESET)"

# =============================================================================
# Observability
# =============================================================================

logs-gateway:
	$(DOCKER_COMPOSE) logs -f gateway | .venv/bin/python -c \
		"import sys, json; [print(json.dumps(json.loads(l), indent=2)) if l.strip().startswith('{') else print(l, end='') for l in sys.stdin]" 2>/dev/null || \
		$(DOCKER_COMPOSE) logs -f gateway

neo4j-browser:
	@open http://localhost:7474 2>/dev/null || xdg-open http://localhost:7474

grafana:
	@open http://localhost:3001 2>/dev/null || xdg-open http://localhost:3001

prometheus:
	@open http://localhost:9090 2>/dev/null || xdg-open http://localhost:9090

# =============================================================================
# Kubernetes
# =============================================================================

K8S_CONTEXT ?= $(shell kubectl config current-context 2>/dev/null || echo "none")

k8s-apply:
	@echo "$(CYAN)Applying to context: $(K8S_CONTEXT)$(RESET)"
	kubectl apply -k k8s/base/
	@echo "$(CYAN)Waiting for gateway rollout...$(RESET)"
	kubectl rollout status deployment/gateway -n sentinel --timeout=120s

k8s-prod:
	@echo "$(CYAN)Applying production overlay to context: $(K8S_CONTEXT)$(RESET)"
	kubectl apply -k k8s/overlays/production/
	kubectl rollout status deployment/gateway -n sentinel --timeout=180s

k8s-delete:
	@echo "$(CYAN)Deleting sentinel namespace from $(K8S_CONTEXT)$(RESET)"
	kubectl delete namespace sentinel --ignore-not-found

k8s-status:
	@echo "=== Pods ==="
	kubectl get pods -n sentinel -o wide
	@echo ""
	@echo "=== HPA ==="
	kubectl get hpa -n sentinel
	@echo ""
	@echo "=== Ingress ==="
	kubectl get ingress -n sentinel

# =============================================================================
# Demo Scenarios
# =============================================================================

demo-a:
	@echo "$(CYAN)Running Scenario A: Rogue Exfiltrator$(RESET)"
	.venv/bin/python agents/demo_a.py

demo-b:
	@echo "$(CYAN)Running Scenario B: Rate Limit Abuser$(RESET)"
	.venv/bin/python agents/demo_b.py

demo-c:
	@echo "$(CYAN)Running Scenario C: Policy Version Rollback$(RESET)"
	.venv/bin/python agents/demo_c.py

# =============================================================================
# Utilities
# =============================================================================

seed-neo4j:
	.venv/bin/python scripts/seed_neo4j.py

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	@echo "$(CYAN)Clean done$(RESET)"
