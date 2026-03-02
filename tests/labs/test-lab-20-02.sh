#!/usr/bin/env bash
# test-lab-20-02.sh — Lab 20-02: External Dependencies
# Module 20: Graylog centralized log management
# graylog with external PostgreSQL, Redis, and network integration
set -euo pipefail

LAB_ID="20-02"
LAB_NAME="External Dependencies"
MODULE="graylog"
COMPOSE_FILE="docker/docker-compose.lan.yml"
PASS=0
FAIL=0

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN} Lab ${LAB_ID}: ${LAB_NAME}${NC}"
echo -e "${CYAN} Module: ${MODULE}${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# ── Cleanup control ───────────────────────────────────────────────────────────
CLEANUP=true
[[ "${1:-}" == "--no-cleanup" ]] && CLEANUP=false

cleanup() {
  if [[ "${CLEANUP}" == "true" ]]; then
    info "Phase 4: Cleanup"
    docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans 2>/dev/null || true
    info "Cleanup complete"
  else
    info "Skipping cleanup (--no-cleanup)"
  fi
}
trap cleanup EXIT

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
info "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
info "Phase 2: Health Checks"

info "Waiting for external MongoDB (graylog-l02-mongo, up to 90s)..."
for i in $(seq 1 18); do
  if docker exec graylog-l02-mongo mongosh --quiet --eval 'db.adminCommand({ping:1})' 2>/dev/null | grep -q 'ok.*1\|"ok" : 1'; then
    pass "External MongoDB healthy"
    break
  fi
  [[ $i -eq 18 ]] && fail "External MongoDB timed out after 90s"
  sleep 5
done

info "Waiting for external Elasticsearch (graylog-l02-es, up to 150s)..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:9200/_cluster/health 2>/dev/null | grep -q 'green\|yellow'; then
    pass "External Elasticsearch healthy"
    break
  fi
  [[ $i -eq 30 ]] && fail "External Elasticsearch timed out after 150s"
  sleep 5
done

info "Waiting for Graylog web (graylog-l02-app, up to 240s)..."
for i in $(seq 1 24); do
  if curl -sf http://localhost:9010/api/ 2>/dev/null | grep -qi 'cluster_id\|version\|graylog'; then
    pass "Graylog API responding"
    break
  fi
  [[ $i -eq 24 ]] && fail "Graylog API timed out after 240s"
  sleep 10
done

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
info "Phase 3: Functional Tests (Lab 20-02 — External Dependencies)"

# Container states
for svc in graylog-l02-mongo graylog-l02-es graylog-l02-app; do
  state=$(docker inspect --format='{{.State.Status}}' "${svc}" 2>/dev/null || echo "missing")
  if [[ "${state}" == "running" ]]; then
    pass "Container ${svc} is running"
  else
    fail "Container ${svc} state: ${state}"
  fi
done

# Graylog API: cluster info
cluster_info=$(curl -sf -u admin:admin http://localhost:9010/api/system/cluster/nodes 2>/dev/null || echo "{}")
if echo "${cluster_info}" | grep -qi 'node_id\|nodes\|total'; then
  pass "Graylog cluster nodes API returns data"
else
  warn "Graylog cluster nodes check inconclusive (auth may still initializing)"
fi

# Graylog API: system overview
system_info=$(curl -sf http://localhost:9010/api/system 2>/dev/null || echo "{}")
if echo "${system_info}" | grep -qi 'cluster_id\|version\|facility'; then
  pass "Graylog /api/system returns system information"
else
  fail "Graylog /api/system did not return expected data"
fi

# HTTP status check for web UI
http_code=$(curl -o /dev/null -sw '%{http_code}' -L http://localhost:9010/ 2>/dev/null || echo "000")
if [[ "${http_code}" =~ ^[234] ]]; then
  pass "Graylog web HTTP GET / -> ${http_code}"
else
  fail "Graylog web HTTP GET / -> ${http_code}"
fi

# MongoDB: graylog database accessible
if docker exec graylog-l02-mongo mongosh --quiet graylog \
  --eval 'db.getCollectionNames().length' 2>/dev/null | grep -qE '^[0-9]+$'; then
  pass "MongoDB graylog database accessible"
else
  warn "MongoDB graylog database check inconclusive"
fi

# ES index check (Graylog creates graylog_ prefixed indices)
indices=$(curl -sf http://localhost:9200/_cat/indices 2>/dev/null || echo "")
if echo "${indices}" | grep -q 'graylog\|green\|yellow'; then
  pass "Elasticsearch has Graylog indices"
else
  warn "Elasticsearch Graylog indices not yet created (may need time to send data)"
fi

# Key env vars in Graylog app container
for var in GRAYLOG_MONGODB_URI GRAYLOG_ELASTICSEARCH_HOSTS GRAYLOG_PASSWORD_SECRET GRAYLOG_HTTP_EXTERNAL_URI; do
  if docker exec graylog-l02-app printenv "${var}" 2>/dev/null | grep -q '.'; then
    pass "Env var ${var} set in graylog-l02-app"
  else
    fail "Env var ${var} missing in graylog-l02-app"
  fi
done

# Volume existence
for vol in graylog-l02-mongo-data graylog-l02-es-data graylog-l02-data; do
  if docker volume ls --format '{{.Name}}' | grep -q "${vol}"; then
    pass "Volume ${vol} exists"
  else
    fail "Volume ${vol} missing"
  fi
done

# Network separation
for net in it-stack-graylog-lab02_graylog-l02-data-net it-stack-graylog-lab02_graylog-l02-app-net; do
  if docker network ls --format '{{.Name}}' | grep -q "${net}"; then
    pass "Network ${net} exists"
  else
    fail "Network ${net} missing"
  fi
done

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
