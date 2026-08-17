#!/usr/bin/env bash
# =============================================================================
# deploy-minikube.sh — Deploy Beer Tracker to a local minikube cluster
#
# Usage:
#   ./scripts/deploy-minikube.sh [--help]
#
# Prerequisites:
#   - minikube running (minikube start)
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

# --- Check minikube is running -----------------------------------------------
echo "Checking minikube status..."
if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
  echo "ERROR: minikube is not running. Start it with: minikube start" >&2
  exit 1
fi

# --- Load .env ---------------------------------------------------------------
if [[ ! -f "$REPO_ROOT/.env" ]]; then
  echo "ERROR: .env file not found at $REPO_ROOT/.env" >&2
  echo "       Copy .env.example to .env and fill in your values." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"

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

kubectl create secret generic "beer-tracker-auth-service-secrets" \
  --namespace="$NAMESPACE" \
  --from-literal=auth-db-password="$POSTGRES_PASSWORD" \
  --from-literal=auth-rs256-private-key="$RSA_KEY_CONTENT" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "beer-tracker-beer-tracking-service-secrets" \
  --namespace="$NAMESPACE" \
  --from-literal=tracking-db-password="$POSTGRES_PASSWORD" \
  --from-literal=internal-api-key="$INTERNAL_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "beer-tracker-health-notification-service-secrets" \
  --namespace="$NAMESPACE" \
  --from-literal=notifications-db-password="$POSTGRES_PASSWORD" \
  --from-literal=internal-api-key="$INTERNAL_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "beer-tracker-statistics-service-secrets" \
  --namespace="$NAMESPACE" \
  --from-literal=statistics-db-password="$POSTGRES_PASSWORD" \
  --from-literal=internal-api-key="$INTERNAL_API_KEY" \
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

echo ""
echo "Deployment complete!"
echo ""
echo "Access the app at: http://$(minikube ip)"
echo ""
echo "Next step: initialise the database schema"
echo "  kubectl run psql-init --rm -it --restart=Never --image=postgres:16 \\"
echo "    --namespace=$NAMESPACE -- psql -h postgresql -U postgres \\"
echo "    -f /dev/stdin < postgres-init/init.sql"
