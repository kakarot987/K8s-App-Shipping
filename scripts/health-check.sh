#!/usr/bin/env bash
# Usage: bash scripts/health-check.sh <deployment-name> <namespace> [timeout-seconds]
set -euo pipefail

DEPLOYMENT="${1:?Usage: $0 <deployment-name> <namespace> [timeout]}"
NAMESPACE="${2:?Usage: $0 <deployment-name> <namespace> [timeout]}"
TIMEOUT="${3:-120}"

kubectl rollout status "deployment/${DEPLOYMENT}" -n "$NAMESPACE" --timeout="${TIMEOUT}s"

# Resolve the actual pod selector instead of assuming it equals the Deployment
# name (the dev Kustomize overlay prefixes names but not the app label).
APP_LABEL=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{.spec.selector.matchLabels.app}')
if [[ -z "$APP_LABEL" ]]; then
  echo 'Deployment is missing the expected app label selector' >&2
  exit 1
fi
SELECTOR="app=${APP_LABEL}"

CRASH_PODS=$(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
  -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.state.waiting.reason}{"\n"}{end}{end}' \
  | grep -c '^CrashLoopBackOff$' || true)
if (( CRASH_PODS > 0 )); then
  echo "Found ${CRASH_PODS} crash-looping pods" >&2
  exit 1
fi

DESIRED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{.spec.replicas}')
AVAILABLE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{.status.availableReplicas}')
AVAILABLE=${AVAILABLE:-0}
if (( AVAILABLE < DESIRED )); then
  echo "Only ${AVAILABLE}/${DESIRED} replicas available" >&2
  exit 1
fi

POD=$(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$POD" ]]; then
  echo 'No running pod found; cannot check /healthz' >&2
  exit 1
fi

kubectl port-forward "pod/${POD}" 18080:3000 -n "$NAMESPACE" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT

HTTP_STATUS=''
for attempt in {1..10}; do
  HTTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
    http://127.0.0.1:18080/healthz || true)
  if [[ "$HTTP_STATUS" == 200 ]]; then
    echo "Health checks passed: ${DEPLOYMENT} in ${NAMESPACE} (${AVAILABLE}/${DESIRED} pods ready)"
    exit 0
  fi
  sleep 1
done

echo "/healthz returned HTTP ${HTTP_STATUS:-unreachable} (expected 200)" >&2
exit 1
