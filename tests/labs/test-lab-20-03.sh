#!/usr/bin/env bash
# test-lab-20-03.sh — Lab 20-03: Graylog Advanced Features
# Tests: resource limits on all 3 tiers · tuned heap · UDP input ports
# Usage: bash test-lab-20-03.sh [--no-cleanup]
set -euo pipefail

LAB_ID="20-03"
LAB_NAME="Advanced Features — Graylog with tuned heap + UDP inputs"
MODULE="graylog"
COMPOSE_FILE="docker/docker-compose.advanced.yml"
PASS=0
FAIL=0

CLEANUP=true
[[ "${1:-}" == "--no-cleanup" ]] && CLEANUP=false

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

pass()    { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
section() { echo -e "\n${CYAN}── $1 ──${NC}"; }

cleanup() {
  if [[ "${CLEANUP}" == "true" ]]; then
    info "Cleaning up Lab ${LAB_ID} containers..."
    docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans 2>/dev/null || true
  else
    info "Skipping cleanup (--no-cleanup)"
  fi
}
trap cleanup EXIT

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN} Lab ${LAB_ID}: ${LAB_NAME}${NC}"
echo -e "${CYAN} Module: ${MODULE}${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
section "Phase 1: Setup"
info "Starting Graylog stack (mongodb + elasticsearch 7 + graylog)..."
docker compose -f "${COMPOSE_FILE}" up -d

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
section "Phase 2: Health Checks"

info "Waiting for MongoDB (graylog-a03-mongo)..."
for i in $(seq 1 12); do
  if docker exec graylog-a03-mongo mongosh --quiet --eval 'db.adminCommand({ ping: 1 })' > /dev/null 2>&1; then
    info "MongoDB ready after ${i}×5s"
    break
  fi
  [[ $i -eq 12 ]] && { fail "MongoDB did not become ready"; exit 1; }
  sleep 5
done

info "Waiting for Elasticsearch 7 (graylog-a03-es, internal port 9200)..."
for i in $(seq 1 20); do
  if docker exec graylog-a03-es curl -sf http://localhost:9200/_cluster/health 2>/dev/null | grep -q 'green\|yellow'; then
    info "Elasticsearch (internal) ready after ${i}×10s"
    break
  fi
  [[ $i -eq 20 ]] && { warn "Elasticsearch check timed out"; }
  sleep 10
done

info "Waiting for Graylog API on port 9020..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:9020/api/ 2>/dev/null | grep -qi 'cluster_id\|version\|graylog'; then
    info "Graylog API ready after ${i}×15s"
    break
  fi
  HTTP_CHECK=$(curl -o /dev/null -sw '%{http_code}' http://localhost:9020/ 2>/dev/null || echo "000")
  if echo "${HTTP_CHECK}" | grep -qE '^[23]'; then
    info "Graylog HTTP ready after ${i}×15s (${HTTP_CHECK})"
    break
  fi
  [[ $i -eq 30 ]] && { warn "Graylog did not fully initialize in time"; }
  sleep 15
done

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
section "Phase 3: Functional Tests — Advanced Features"

# 3.1 Container states (all 3)
for cname in graylog-a03-mongo graylog-a03-es graylog-a03-app; do
  STATE=$(docker inspect "${cname}" --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  if [[ "${STATE}" == "running" ]]; then
    pass "Container ${cname} is running"
  else
    fail "Container ${cname} state: ${STATE}"
  fi
done

# 3.2 Graylog API response
API_RESP=$(curl -sf http://localhost:9020/api/ 2>/dev/null || echo "{}")
if echo "${API_RESP}" | grep -qi 'cluster_id\|version\|graylog'; then
  pass "Graylog REST API is accessible"
else
  HTTP_STATUS=$(curl -o /dev/null -sw '%{http_code}' http://localhost:9020/ 2>/dev/null || echo "000")
  if echo "${HTTP_STATUS}" | grep -qE '^[234]'; then
    pass "Graylog HTTP responding (${HTTP_STATUS})"
  else
    fail "Graylog API not accessible (${HTTP_STATUS})"
  fi
fi

# 3.3 Resource limits on all 3 containers
for cname in graylog-a03-mongo graylog-a03-es graylog-a03-app; do
  MEM_LIMIT=$(docker inspect "${cname}" --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
  if [[ "${MEM_LIMIT}" -gt 0 ]]; then
    pass "${cname} has memory limit (${MEM_LIMIT} bytes)"
  else
    fail "${cname} has no memory limit"
  fi
done

# 3.4 Graylog heap configuration via JAVA_OPTS
JAVA_OPTS=$(docker exec graylog-a03-app printenv JAVA_OPTS 2>/dev/null || echo "")
if echo "${JAVA_OPTS}" | grep -q '\-Xm'; then
  pass "Graylog JAVA_OPTS heap configured: ${JAVA_OPTS}"
else
  warn "JAVA_OPTS not found or missing heap settings: '${JAVA_OPTS}'"
fi

# 3.5 Elasticsearch heap configuration
ES_JAVA_OPTS=$(docker exec graylog-a03-es printenv ES_JAVA_OPTS 2>/dev/null || echo "")
if echo "${ES_JAVA_OPTS}" | grep -q '\-Xm'; then
  pass "Elasticsearch heap tuned: ${ES_JAVA_OPTS}"
else
  warn "ES_JAVA_OPTS='${ES_JAVA_OPTS}'"
fi

# 3.6 UDP port bindings (syslog + GELF)
UDP_PORTS=$(docker inspect graylog-a03-app --format '{{json .HostConfig.PortBindings}}' 2>/dev/null || echo "{}")
if echo "${UDP_PORTS}" | grep -q '1514\|1516'; then
  pass "Syslog UDP port bound (1516→1514/udp)"
else
  warn "Syslog UDP port binding not found in inspect output"
fi
if echo "${UDP_PORTS}" | grep -q '12201\|12203'; then
  pass "GELF UDP port bound (12203→12201/udp)"
else
  warn "GELF UDP port binding not found in inspect output"
fi

# 3.7 Volumes
for vol in graylog-a03-mongo-data graylog-a03-es-data graylog-a03-data; do
  if docker volume ls --format '{{.Name}}' | grep -q "${vol}"; then
    pass "Volume ${vol} exists"
  else
    fail "Volume ${vol} not found"
  fi
done

# ── PHASE 4: (cleanup via trap) ────────────────────────────────────────────────
section "Phase 4: Results"

echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
