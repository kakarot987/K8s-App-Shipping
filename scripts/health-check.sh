#!/usr/bin/env bash
# scripts/health-check.sh
# Post-deployment readiness verification
# Usage: ./health-check.sh <deployment-name> <namespace> [timeout-seconds]
#
# Checks:
#   1. All pods in the deployment reach Ready state
#   2. No pods in CrashLoopBackOff
#   3. /healthz endpoint returns HTTP 200

set -euo pipefail

DEPLOYMENT="${1:?Usage: $0 <deployment-name> <namespace> [timeout]}"
NAMESPACE="${2:?Usage: $0 <deployment-name> <namespace> [timeout]}"
TIMEOUT="${3:-120}"
INTERVAL=5

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
fail() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Health Check: $DEPLOYMENT / $NAMESPACE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

##############################################################################
# 1. Wait for deployment rollout to complete
##############################################################################
log "Waiting for rollout to complete (timeout: ${TIMEOUT}s)..."

if ! kubectl rollout status deployment/"${DEPLOYMENT}" \
     -n "${NAMESPACE}" \
     --timeout="${TIMEOUT}s"; then
  fail "Rollout did not complete within ${TIMEOUT}s"
fi

log "Rollout complete"

##############################################################################
# 2. Check for CrashLoopBackOff pods
##############################################################################
log "Checking for crash-looping pods..."

CRASH_PODS=$(kubectl get pods \
  -n "${NAMESPACE}" \
  -l "app=${DEPLOYMENT}" \
  --field-selector=status.phase=Running \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.state.waiting.reason}{"\n"}{end}{end}' \
  2>/dev/null | grep -c "CrashLoopBackOff" || true)

if [[ "${CRASH_PODS}" -gt 0 ]]; then
  warn "Crash-looping pods detected:"
  kubectl get pods -n "${NAMESPACE}" -l "app=${DEPLOYMENT}"
  fail "${CRASH_PODS} pod(s) in CrashLoopBackOff"
fi

log "No crash-looping pods"

##############################################################################
# 3. Confirm desired vs available replica count
##############################################################################
log "Verifying replica counts..."

DESIRED=$(kubectl get deployment "${DEPLOYMENT}" \
  -n "${NAMESPACE}" \
  -o jsonpath='{.spec.replicas}')
AVAILABLE=$(kubectl get deployment "${DEPLOYMENT}" \
  -n "${NAMESPACE}" \
  -o jsonpath='{.status.availableReplicas}')

if [[ "${AVAILABLE}" -lt "${DESIRED}" ]]; then
  fail "Only ${AVAILABLE}/${DESIRED} replicas available"
fi

log "${AVAILABLE}/${DESIRED} replicas available"

##############################################################################
# 4. HTTP healthcheck via kubectl port-forward
##############################################################################
log "Running HTTP health check..."

# Pick the first running pod
POD=$(kubectl get pod \
  -n "${NAMESPACE}" \
  -l "app=${DEPLOYMENT}" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "${POD}" ]]; then
  warn "No running pod found — skipping HTTP check"
else
  # Port-forward in background
  kubectl port-forward pod/"${POD}" 18080:3000 -n "${NAMESPACE}" &>/dev/null &
  PF_PID=$!
  sleep 2

  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 5 http://localhost:18080/healthz || echo "000")

  kill "${PF_PID}" 2>/dev/null || true

  if [[ "${HTTP_STATUS}" == "200" ]]; then
    log "/healthz returned HTTP ${HTTP_STATUS}"
  else
    fail "/healthz returned HTTP ${HTTP_STATUS} (expected 200)"
  fi
fi

##############################################################################
# Summary
##############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "All checks passed for ${DEPLOYMENT} in ${NAMESPACE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
