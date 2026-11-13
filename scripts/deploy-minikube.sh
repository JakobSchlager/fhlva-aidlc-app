#!/usr/bin/env bash
# =============================================================================
# deploy-minikube.sh — Deploy Beer Tracker to a local minikube cluster
#
# Usage:
#   ./scripts/deploy-minikube.sh [--help] [--smoke-test]
#
# Prerequisites:
#   - minikube running or devcontainer-minikube-start available
#   - kubectl configured for minikube
#   - helm >= 3.10
#   - .env file at repo root (copy from .env.example and fill values)
#
# This script is idempotent — safe to re-run.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="beer-tracker"
RELEASE="beer-tracker"
CHART="$REPO_ROOT/charts/beer-tracker"

# --- Help -------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit 0
fi

# --- Check minikube is running (start if needed) ------------------------------
echo "Checking minikube status..."
if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
  echo "minikube is not running. Starting minikube..."
  if command -v devcontainer-minikube-start &>/dev/null; then
    devcontainer-minikube-start
  else
    minikube start
  fi
fi

# --- Load .env ---------------------------------------------------------------
if [[ ! -f "$REPO_ROOT/.env" ]]; then
  echo "ERROR: .env file not found at $REPO_ROOT/.env" >&2
  echo "       Copy .env.example to .env and fill in your values." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"

# In devcontainers, VS Code may write a credsStore to ~/.docker/config.json that fails outside VS Code IPC,
# causing Helm OCI registry fetches to fail with exit status 255.
if [[ -z "${DOCKER_CONFIG:-}" ]] && grep -q "dev-containers-" "$HOME/.docker/config.json" 2>/dev/null; then
  CREDS_STORE=$(grep -o '"credsStore": *"[^"]*"' "$HOME/.docker/config.json" | cut -d'"' -f4)
  if ! echo "https://registry-1.docker.io/v2/" | "docker-credential-$CREDS_STORE" get &>/dev/null; then
    DOCKER_CONFIG_FALLBACK="/tmp/docker-fallback"
    mkdir -p "$DOCKER_CONFIG_FALLBACK"
    echo '{}' > "$DOCKER_CONFIG_FALLBACK/config.json"
    export DOCKER_CONFIG="$DOCKER_CONFIG_FALLBACK"
  fi
fi

# Validate required variables
: "${POSTGRES_PASSWORD:?ERROR: POSTGRES_PASSWORD is not set in .env}"
: "${INTERNAL_API_KEY:?ERROR: INTERNAL_API_KEY is not set in .env}"
: "${AUTH_RSA_KEY_PATH:?ERROR: AUTH_RSA_KEY_PATH is not set in .env}"

if [[ ! -f "$REPO_ROOT/$AUTH_RSA_KEY_PATH" && ! -f "$AUTH_RSA_KEY_PATH" ]]; then
  # Try absolute path too
  RSA_KEY_ABS="$REPO_ROOT/secrets/auth-rs256-private-key.pem"
else
  RSA_KEY_ABS="${AUTH_RSA_KEY_PATH#./}"
  RSA_KEY_ABS="$REPO_ROOT/$RSA_KEY_ABS"
fi

if [[ ! -f "$RSA_KEY_ABS" ]]; then
  echo "ERROR: RSA private key not found at $RSA_KEY_ABS" >&2
  echo "       Generate with: openssl genrsa -out secrets/auth-rs256-private-key.pem 2048" >&2
  exit 1
fi

# --- Enable ingress addon ----------------------------------------------------
echo "Enabling minikube ingress addon..."
minikube addons enable ingress

# --- Build images directly into minikube -------------------------------------
# minikube image build works with both Docker and Podman; avoids the need to
# eval minikube docker-env, which only works with real Docker (not Podman CLI).
echo "Building Docker images..."

declare -A SERVICE_DIRS=(
  [auth-service]="$REPO_ROOT/services/auth-service"
  [beer-tracking-service]="$REPO_ROOT/services/beer-tracking-service"
  [health-notification-service]="$REPO_ROOT/services/health-notification-service"
  [statistics-service]="$REPO_ROOT/services/statistics-service"
  [frontend]="$REPO_ROOT/frontend"
)

for svc in "${!SERVICE_DIRS[@]}"; do
  echo "  Building $svc..."
  minikube image build -t "$svc:latest" "${SERVICE_DIRS[$svc]}"
done

# --- Create namespace --------------------------------------------------------
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$NAMESPACE" \
  app.kubernetes.io/managed-by=Helm --overwrite
kubectl annotate namespace "$NAMESPACE" \
  meta.helm.sh/release-name="$RELEASE" \
  meta.helm.sh/release-namespace="$NAMESPACE" --overwrite

# --- Create Kubernetes Secrets -----------------------------------------------
echo "Creating Kubernetes Secrets..."

RSA_KEY_CONTENT=$(cat "$RSA_KEY_ABS")

# Same name and keys as deploy-azure.sh: the charts consume this Secret via envFrom.
kubectl create secret generic beer-tracker-secrets \
  --namespace="$NAMESPACE" \
  --from-literal=auth-rs256-private-key="$RSA_KEY_CONTENT" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=INTERNAL_API_KEY="$INTERNAL_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Install Bitnami PostgreSQL (if not already installed) -------------------
echo "Setting up PostgreSQL..."
if ! helm status postgresql --namespace="$NAMESPACE" &>/dev/null; then
  helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
  helm repo update
  helm install postgresql bitnami/postgresql \
    --namespace="$NAMESPACE" \
    --set auth.postgresPassword="$POSTGRES_PASSWORD" \
    --set auth.username=postgres \
    --wait --timeout=5m
fi

# --- Initialize databases (idempotent) ---------------------------------------
echo "Initializing databases..."
kubectl exec -i -n "$NAMESPACE" postgresql-0 -- \
  env PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres \
  < "$REPO_ROOT/postgres-init/init.sql"

# --- Helm dependency update --------------------------------------------------
echo "Updating Helm dependencies..."
helm dependency update "$CHART"

# --- Deploy ------------------------------------------------------------------
echo "Deploying Beer Tracker..."
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace="$NAMESPACE" \
  --create-namespace \
  -f "$REPO_ROOT/values-minikube.yaml" \
  --wait --timeout=10m

# --- Smoke test (optional: --smoke-test or SMOKE_TEST=true) ------------------
if [[ "${1:-}" == "--smoke-test" || "${SMOKE_TEST:-false}" == "true" ]]; then
  echo ""
  echo "Running smoke test..."
  kubectl apply -k "$REPO_ROOT/load/" -n "$NAMESPACE"
  kubectl delete job k6-load -n "$NAMESPACE" 2>/dev/null || true
  kubectl apply -f "$REPO_ROOT/load/k8s/job.yaml" -n "$NAMESPACE"
  kubectl wait --for=condition=complete job/k6-load -n "$NAMESPACE" --timeout=3m
  kubectl logs job/k6-load -n "$NAMESPACE"
fi

echo ""
echo "Deployment complete!"
echo ""
echo "Access the app at: http://$(minikube ip)"
