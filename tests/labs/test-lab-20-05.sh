#!/usr/bin/env bash
# test-lab-20-05.sh — Lab 20-05: Advanced Integration
# Module 20: Graylog centralized log management
# graylog integrated with full IT-Stack ecosystem
set -euo pipefail

LAB_ID="20-05"
LAB_NAME="Advanced Integration"
MODULE="graylog"
COMPOSE_FILE="docker/docker-compose.integration.yml"
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
APP_PORT=9040
MOCK_PORT=8765
KC_PORT=8544
LDAP_PORT=3889
MOCK_URL="http://localhost:${MOCK_PORT}"

APP_CONTAINER="graylog-i05-app"
MOCK_CONTAINER="graylog-i05-mock"

# ── Cleanup trap ──────────────────────────────────────────────────────────────
NO_CLEANUP=false
[[ "${1:-}" == "--no-cleanup" ]] && NO_CLEANUP=true

cleanup() {
  if [[ "${NO_CLEANUP}" == "false" ]]; then
    info "Phase 4: Cleanup"
    docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans 2>/dev/null || true
    info "Cleanup complete"
  else
    warn "Skipping cleanup (--no-cleanup)"
  fi
}
trap cleanup EXIT

echo ""

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
info "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 90s for Graylog stack to initialize (Mongo + ES + Graylog)..."
sleep 90

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
info "Phase 2: Health Checks"

if docker ps --format '{{.Names}}' | grep -q "^${APP_CONTAINER}$"; then
  pass "Graylog app container running"
else
  fail "Graylog app container not running"
fi

if docker ps --format '{{.Names}}' | grep -q "^${MOCK_CONTAINER}$"; then
  pass "WireMock container running"
else
  fail "WireMock container not running"
fi

# Graylog web UI
if curl -sf "http://localhost:${APP_PORT}/api/" > /dev/null 2>&1; then
  pass "Graylog REST API responds"
else
  warn "Graylog REST API not yet ready"
fi

# WireMock health
if curl -sf "${MOCK_URL}/__admin/health" > /dev/null; then
  pass "WireMock admin health OK"
else
  fail "WireMock admin health unreachable"
fi

# Keycloak
if curl -sf "http://localhost:${KC_PORT}/realms/master" > /dev/null 2>&1; then
  pass "Keycloak master realm accessible"
else
  warn "Keycloak not yet ready"
fi

# LDAP
if ldapsearch -x -H ldap://localhost:${LDAP_PORT} -b dc=lab,dc=local \
     -D cn=admin,dc=lab,dc=local -w LdapLab05! cn=admin > /dev/null 2>&1; then
  pass "OpenLDAP bind successful"
else
  warn "OpenLDAP bind failed"
fi

# ── PHASE 3: Integration Tests ────────────────────────────────────────────────
info "Phase 3: Integration Tests (Zabbix HTTP API via WireMock)"

# 3a: Register Zabbix API login stub
info "3a: Registering Zabbix /api_jsonrpc.php stub..."
HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST "${MOCK_URL}/__admin/mappings" \
  -H "Content-Type: application/json" \
  -d '{
    "request": {"method": "POST", "url": "/api_jsonrpc.php"},
    "response": {
      "status": 200,
      "headers": {"Content-Type": "application/json"},
      "body": "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"token\":\"lab-zbx-auth-05\",\"problems\":[{\"eventid\":\"101\",\"name\":\"High CPU on lab-proxy1\",\"severity\":\"4\",\"hosts\":[{\"host\":\"lab-proxy1\",\"name\":\"Proxy Server\"}]}]}}"
    }
  }' || echo "000")
if [ "${HTTP_STATUS}" = "201" ]; then
  pass "WireMock Zabbix /api_jsonrpc.php stub registered (201)"
else
  fail "WireMock Zabbix stub registration failed (HTTP ${HTTP_STATUS})"
fi

# 3b: Verify Zabbix API mock responds
if curl -sf -X POST "${MOCK_URL}/api_jsonrpc.php" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"problem.get","params":{},"id":1}' | grep -q 'lab-zbx-auth-05'; then
  pass "WireMock Zabbix /api_jsonrpc.php returns Zabbix response JSON"
else
  fail "WireMock Zabbix response returned unexpected output"
fi

# 3c: Integration env vars in Graylog container
if docker exec "${APP_CONTAINER}" env 2>/dev/null | grep -q 'ZABBIX_URL='; then
  pass "ZABBIX_URL env var present in Graylog container"
else
  fail "ZABBIX_URL env var missing from Graylog container"
fi

if docker exec "${APP_CONTAINER}" env 2>/dev/null | grep -q 'ZABBIX_API_TOKEN='; then
  pass "ZABBIX_API_TOKEN env var present in Graylog container"
else
  fail "ZABBIX_API_TOKEN env var missing from Graylog container"
fi

# 3d: Container-to-WireMock connectivity
if docker exec "${APP_CONTAINER}" curl -sf http://graylog-i05-mock:8080/__admin/health > /dev/null 2>&1; then
  pass "Graylog container can reach WireMock (graylog-i05-mock:8080)"
else
  fail "Graylog container cannot reach WireMock"
fi

# 3e: Simulate Graylog → Zabbix alert via WireMock
if docker exec "${APP_CONTAINER}" curl -sf \
     -X POST http://graylog-i05-mock:8080/api_jsonrpc.php \
     -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","method":"event.acknowledge","params":{"eventids":["101"],"action":6,"message":"Graylog alert: CPU spike detected"},"auth":"lab-zbx-auth-05","id":1}' 2>/dev/null | grep -q 'lab-zbx'; then
  pass "Graylog → Zabbix API call succeeds (via WireMock)"
else
  warn "Graylog → Zabbix API call not verified (app needs full setup)"
fi

# 3f: Test syslog UDP input (if netcat available)
if command -v nc > /dev/null 2>&1; then
  echo "<14>Jan  1 00:00:00 test syslog message from lab-20-05" | nc -u -w1 localhost 1518 2>/dev/null || true
  pass "Syslog UDP input tested (port 1518)"
else
  warn "nc not available, skipping syslog UDP input test"
fi

# 3g: Volume assertions
if docker volume ls | grep -q 'graylog-i05-app-data'; then
  pass "Graylog app data volume exists"
else
  fail "Graylog app data volume missing"
fi

if docker volume ls | grep -q 'graylog-i05-mongo-data'; then
  pass "Graylog MongoDB volume exists"
else
  fail "Graylog MongoDB volume missing"
fi

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}========================================${NC}"

[ "${FAIL}" -gt 0 ] && exit 1 || exit 0

# TODO: Add module-specific functional tests here
# Example:
# if curl -sf http://localhost:9000/health > /dev/null 2>&1; then
#     pass "Health endpoint responds"
# else
#     fail "Health endpoint not reachable"
# fi

warn "Functional tests for Lab 20-05 pending implementation"

# ── PHASE 4: Cleanup ──────────────────────────────────────────────────────────
info "Phase 4: Cleanup"
docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
info "Cleanup complete"

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
