#!/usr/bin/env bash
# =============================================================================
# smoke-test.sh — Run k6 smoke test against Beer Tracker in Kubernetes
#
# Usage:
#   ./scripts/smoke-test.sh [--help]
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-beer-tracker}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,6p' "$0" | sed 's/^# \?//'
  exit 0
fi

echo "Applying load ConfigMaps (namespace: $NAMESPACE)..."
kubectl apply -k "$REPO_ROOT/load/" -n "$NAMESPACE"

echo "Restarting k6 smoke test Job..."
kubectl delete job k6-load -n "$NAMESPACE" 2>/dev/null || true
kubectl apply -f "$REPO_ROOT/load/k8s/job.yaml" -n "$NAMESPACE"

echo "Waiting for k6-load pod..."
kubectl wait --for=condition=ready pod -l app=k6-load -n "$NAMESPACE" --timeout=60s 2>/dev/null || true

echo "Following smoke test logs..."
kubectl logs -f job/k6-load -n "$NAMESPACE"
