#!/usr/bin/env bash
# test-lab-20-01.sh — Lab 20-01: Standalone
# Module 20: Graylog centralized log management
# Basic graylog functionality in complete isolation
set -euo pipefail

LAB_ID="20-01"
LAB_NAME="Standalone"
MODULE="graylog"
COMPOSE_FILE="docker/docker-compose.standalone.yml"
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

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
info "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 30s for ${MODULE} to initialize..."
sleep 30

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
info "Phase 2: Health Checks"

if docker compose -f "${COMPOSE_FILE}" ps | grep -q "running\|Up"; then
    pass "Container is running"
else
    fail "Container is not running"
fi

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
info "Phase 3: Functional Tests (Lab 01 — Standalone)"

GRAYLOG_URL="http://localhost:9000"
NO_CLEANUP=${NO_CLEANUP:-0}

cleanup() {
    if [ "${NO_CLEANUP}" = "1" ]; then
        info "NO_CLEANUP=1 — skipping teardown"
    else
        info "Phase 4: Cleanup"
        docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans 2>/dev/null || true
        info "Cleanup complete"
    fi
}
trap cleanup EXIT

section() { echo -e "\n${CYAN}## $1${NC}"; }

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
section "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 120s for Graylog to initialize (MongoDB + Elasticsearch + Graylog)..."
sleep 120

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
section "Phase 2: Health Checks"

if docker compose -f "${COMPOSE_FILE}" ps graylog-s01-mongo 2>/dev/null | grep -q 'Up\|running'; then
    pass "2.1 MongoDB (graylog-s01-mongo) is up"
else
    fail "2.1 MongoDB is not running"
fi

if docker compose -f "${COMPOSE_FILE}" ps graylog-s01-es 2>/dev/null | grep -q 'Up\|running'; then
    pass "2.2 Elasticsearch (graylog-s01-es) is up"
else
    fail "2.2 Elasticsearch is not running"
fi

if docker compose -f "${COMPOSE_FILE}" ps graylog-s01-app 2>/dev/null | grep -q 'Up\|running'; then
    pass "2.3 Graylog (graylog-s01-app) is up"
else
    fail "2.3 Graylog is not running"
fi

info "Waiting 30s more for Graylog API to become ready..."
sleep 30

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
section "Phase 3: Functional Tests"

# 3.1 Graylog web UI root
HTTP_CODE=$(curl -o /dev/null -sw '%{http_code}' -L "${GRAYLOG_URL}/" 2>/dev/null || echo 000)
if echo "${HTTP_CODE}" | grep -q '^[23]'; then
    pass "3.1 Graylog web UI accessible (HTTP ${HTTP_CODE})"
else
    fail "3.1 Graylog web UI not accessible (HTTP ${HTTP_CODE})"
fi

# 3.2 Graylog REST API responds
HTTP_API=$(curl -o /dev/null -sw '%{http_code}' \
    -u admin:admin_lab_password \
    -H 'Accept: application/json' \
    "${GRAYLOG_URL}/api/" \
    2>/dev/null || echo 000)
if echo "${HTTP_API}" | grep -q '^[23]'; then
    pass "3.2 Graylog REST API responds (HTTP ${HTTP_API})"
else
    warn "3.2 Graylog REST API not ready yet (HTTP ${HTTP_API})"
fi

# 3.3 Graylog system info
SYS_RESPONSE=$(curl -sf \
    -u admin:admin_lab_password \
    -H 'Accept: application/json' \
    "${GRAYLOG_URL}/api/system" \
    2>/dev/null || echo '')
if echo "${SYS_RESPONSE}" | grep -qi 'cluster_id\|version\|hostname'; then
    pass "3.3 Graylog system API returned cluster info"
else
    warn "3.3 Graylog system API not yet ready"
fi

# 3.4 Graylog cluster nodes
CLUSTER_RESPONSE=$(curl -sf \
    -u admin:admin_lab_password \
    -H 'Accept: application/json' \
    "${GRAYLOG_URL}/api/system/cluster/nodes" \
    2>/dev/null || echo '')
if echo "${CLUSTER_RESPONSE}" | grep -qi 'node_id\|nodes'; then
    pass "3.4 Graylog cluster node list returned"
else
    warn "3.4 Graylog cluster nodes not yet visible"
fi

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
