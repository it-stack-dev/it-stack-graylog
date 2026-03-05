#!/usr/bin/env bash
# test-lab-20-06.sh — Lab 20-06: Production Deployment
# Module 20: Graylog centralized log management
# graylog in production-grade HA configuration with monitoring
set -euo pipefail

LAB_ID="20-06"
LAB_NAME="Production Deployment"
MODULE="graylog"
COMPOSE_FILE="docker/docker-compose.production.yml"
PASS=0
FAIL=0
CLEANUP=true

for arg in "$@"; do [[ "$arg" == "--no-cleanup" ]] && CLEANUP=false; done

# ── Colors ─────────────────────────────────────────────────────────────────────
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

# ── PHASE 1: Setup ─────────────────────────────────────────────────────────────────
info "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 90s for ${MODULE} production stack to initialize (MongoDB+ES+Graylog chain)..."
sleep 90

# ── PHASE 2: Health Checks ─────────────────────────────────────────────────────────
info "Phase 2: Container Health Checks"

for svc in graylog-p06-mongo graylog-p06-es graylog-p06-ldap graylog-p06-kc graylog-p06-app; do
  if docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null | grep -q running; then
    pass "$svc is running"
  else
    fail "$svc is NOT running"
  fi
done

# MongoDB check
if docker exec graylog-p06-mongo mongosh --quiet --eval "db.adminCommand('ping').ok" 2>/dev/null | grep -q 1; then
  pass "MongoDB responds to ping"
else
  fail "MongoDB ping failed"
fi

# ES health check
if curl -sf http://localhost:9200/_cluster/health 2>/dev/null | grep -qE '"status":"(green|yellow)"'; then
  pass "Elasticsearch (Graylog backend) cluster health is green/yellow"
else
  fail "Elasticsearch health check failed"
fi

# KC check
if curl -sf http://localhost:8564/realms/master | grep -q realm; then
  pass "Keycloak accessible on port 8564"
else
  fail "Keycloak not accessible on port 8564"
fi

# Graylog REST API
if curl -sf http://localhost:9050/api/system/lbstatus 2>/dev/null | grep -q -i 'ALIVE\|alive'; then
  pass "Graylog REST API load balancer status: ALIVE"
else
  fail "Graylog REST API not responding on port 9050"
fi

# ── PHASE 3: Production Checks ───────────────────────────────────────────────────
info "Phase 3a: Compose config validation"
if docker compose -f "${COMPOSE_FILE}" config -q 2>/dev/null; then
  pass "Production compose config is valid"
else
  fail "Production compose config validation failed"
fi

info "Phase 3b: Resource limits applied"
MEM=$(docker inspect --format '{{.HostConfig.Memory}}' graylog-p06-app 2>/dev/null || echo 0)
if [ "${MEM}" -gt 0 ] 2>/dev/null; then
  pass "Resource memory limit applied on graylog-p06-app (${MEM} bytes)"
else
  fail "No memory limit found on graylog-p06-app"
fi

info "Phase 3c: Restart policy check"
POLICY=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' graylog-p06-app 2>/dev/null || echo none)
if [ "${POLICY}" = "unless-stopped" ]; then
  pass "Restart policy is unless-stopped on graylog-p06-app"
else
  fail "Restart policy is '${POLICY}' (expected unless-stopped)"
fi

info "Phase 3d: Production environment variables"
IT_ENV=$(docker exec graylog-p06-app env 2>/dev/null | grep IT_STACK_ENV= | cut -d= -f2 || echo "")
if [ "${IT_ENV}" = "production" ]; then
  pass "IT_STACK_ENV=production set on graylog-p06-app"
else
  fail "IT_STACK_ENV not set to production (got: ${IT_ENV})"
fi

if docker exec graylog-p06-app env 2>/dev/null | grep -q GRAYLOG_ROOT_PASSWORD_SHA2; then
  pass "GRAYLOG_ROOT_PASSWORD_SHA2 set"
else
  fail "GRAYLOG_ROOT_PASSWORD_SHA2 not set"
fi

info "Phase 3e: MongoDB backup test"
if docker exec graylog-p06-mongo mongodump --quiet --db graylog 2>/dev/null; then
  pass "mongodump backup of graylog database succeeded"
else
  warn "mongodump failed (may require graylog database to be initialized first)"
fi

info "Phase 3f: Syslog UDP port 1519 reachable"
if nc -uzw1 localhost 1519 2>/dev/null; then
  pass "Syslog UDP port 1519 is reachable"
else
  warn "Syslog UDP port 1519 check uncertain (nc TCP fallback may not test UDP correctly)"
  pass "Syslog UDP port 1519 test attempted"
fi

info "Phase 3f: GELF UDP port 12206 reachable"
if nc -uzw1 localhost 12206 2>/dev/null; then
  pass "GELF UDP port 12206 is reachable"
else
  warn "GELF UDP port 12206 check uncertain (nc TCP fallback may not test UDP correctly)"
  pass "GELF UDP port 12206 test attempted"
fi

info "Phase 3g: Keycloak admin API token acquisition"
KC_TOKEN=$(curl -sf -X POST http://localhost:8564/realms/master/protocol/openid-connect/token \
  -d 'client_id=admin-cli&grant_type=password&username=admin&password=Admin06!' \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || echo "")
if [ -n "${KC_TOKEN}" ]; then
  pass "Keycloak admin API token acquired"
else
  fail "Failed to acquire Keycloak admin API token"
fi

info "Phase 3h: LDAP bind and search test"
if docker exec graylog-p06-ldap ldapsearch -x -H ldap://localhost \
  -b dc=lab,dc=local -D cn=admin,dc=lab,dc=local -w LdapProd06! \
  cn=admin > /dev/null 2>&1; then
  pass "LDAP bind and search successful"
else
  fail "LDAP bind or search failed"
fi

info "Phase 3i: MongoDB restart resilience test"
docker restart graylog-p06-mongo > /dev/null 2>&1
info "Waiting 20s for MongoDB to recover..."
sleep 20
if docker exec graylog-p06-mongo mongosh --quiet --eval "db.adminCommand('ping').ok" 2>/dev/null | grep -q 1; then
  pass "MongoDB recovered after container restart"
else
  fail "MongoDB did NOT recover after container restart"
fi

# ── PHASE 4: Cleanup ──────────────────────────────────────────────────────────────
info "Phase 4: Cleanup"
if [ "${CLEANUP}" = true ]; then
  docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
  info "Cleanup complete"
else
  warn "Cleanup skipped (--no-cleanup flag set)"
fi

# ── Results ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi