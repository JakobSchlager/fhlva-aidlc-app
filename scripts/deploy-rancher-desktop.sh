#!/usr/bin/env bash
# =============================================================================
# deploy-rancher-desktop.sh — Deploy Beer Tracker to Rancher Desktop
#
# Usage:
#   ./scripts/deploy-rancher-desktop.sh [--help]
#
# Prerequisites:
#   - Rancher Desktop running with Kubernetes enabled
#   - kubectl configured for rancher-desktop context
#   - helm >= 3.10
#   - Docker or nerdctl (Rancher Desktop container engine)
#   - .env file at repo root (copy from .env.example and fill values)
#
# This script is idempotent — safe to re-run.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="beer-tracker"
RELEASE="beer-tracker"
CHART="$REPO_ROOT/charts/beer-tracker"

# --- Help --------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,14p' "$0" | sed 's/^# \?//'
  exit 0
fi

# --- Check Rancher Desktop Kubernetes is running -----------------------------
echo "Checking Rancher Desktop Kubernetes status..."

# Auto-detect Windows kubeconfig if running inside WSL without a local kubeconfig
if [[ -z "${KUBECONFIG:-}" && ! -f "$HOME/.kube/config" ]]; then
  if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    for win_user in /mnt/c/Users/*; do
      if [[ -f "$win_user/.kube/config" ]]; then
        export KUBECONFIG="$win_user/.kube/config"
        break
      fi
    done
  fi
fi

# Switch to rancher-desktop context if available and not already active
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [[ "$CURRENT_CONTEXT" != "rancher-desktop" ]]; then
  if kubectl config get-contexts rancher-desktop &>/dev/null; then
    echo "Switching kubectl context to 'rancher-desktop' (was '$CURRENT_CONTEXT')..."
    kubectl config use-context rancher-desktop >/dev/null
  fi
fi

if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: Cannot reach Kubernetes cluster." >&2
  echo "       Ensure Rancher Desktop is running and Kubernetes is enabled in settings." >&2
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

# --- Ingress Controller ------------------------------------------------------
echo "Checking Ingress controller..."
INGRESS_CLASS=""

if kubectl get ingressclass traefik &>/dev/null; then
  INGRESS_CLASS="traefik"
elif kubectl get ingressclass nginx &>/dev/null; then
  INGRESS_CLASS="nginx"
else
  # Check if Traefik can be enabled via rdctl if available
  if command -v rdctl &>/dev/null; then
    echo "  No IngressClass found. Attempting to enable built-in Traefik via rdctl..."
    rdctl set --kubernetes.options.traefik=true 2>/dev/null || true
    echo "  Waiting for Traefik ingress controller to be ready..."
    kubectl wait --namespace kube-system \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/name=traefik \
      --timeout=120s 2>/dev/null || true
  fi

  if kubectl get ingressclass traefik &>/dev/null; then
    INGRESS_CLASS="traefik"
  elif kubectl get ingressclass nginx &>/dev/null; then
    INGRESS_CLASS="nginx"
  else
    INGRESS_CLASS="traefik"
    echo "  NOTE: Defaulting ingress class to 'traefik' (Rancher Desktop built-in)."
    echo "        Ensure 'Enable Traefik' is active in Rancher Desktop Settings -> Kubernetes."
  fi
fi
echo "Using ingress class: $INGRESS_CLASS"

# --- Build container images --------------------------------------------------
echo "Building container images..."

BUILDER=""
if command -v docker &>/dev/null && docker info &>/dev/null; then
  BUILDER="docker"
elif command -v nerdctl &>/dev/null && nerdctl info &>/dev/null; then
  BUILDER="nerdctl"
else
  echo "ERROR: Neither 'docker' nor 'nerdctl' is running or available." >&2
  echo "       Ensure Rancher Desktop container engine (dockerd or containerd) is running." >&2
  exit 1
fi

declare -A SERVICE_DIRS=(
  [auth-service]="$REPO_ROOT/services/auth-service"
  [beer-tracking-service]="$REPO_ROOT/services/beer-tracking-service"
  [health-notification-service]="$REPO_ROOT/services/health-notification-service"
  [statistics-service]="$REPO_ROOT/services/statistics-service"
  [frontend]="$REPO_ROOT/frontend"
)

for svc in "${!SERVICE_DIRS[@]}"; do
  echo "  Building $svc ($BUILDER)..."
  if [[ "$BUILDER" == "docker" ]]; then
    docker build -t "$svc:latest" "${SERVICE_DIRS[$svc]}"
  else
    nerdctl --namespace k8s.io build -t "$svc:latest" "${SERVICE_DIRS[$svc]}"
  fi
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

# Same name and keys as deploy-minikube.sh and deploy-azure.sh:
# the charts consume this Secret via envFrom.
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
kubectl rollout status statefulset/postgresql -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
kubectl exec -i -n "$NAMESPACE" postgresql-0 -c postgresql -- \
  env PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U postgres \
  < "$REPO_ROOT/postgres-init/init.sql"

# --- Helm dependency update --------------------------------------------------
echo "Updating Helm dependencies..."
helm dependency update "$CHART"

# --- Deploy ------------------------------------------------------------------
echo "Deploying Beer Tracker..."
VALUES_FILE="$REPO_ROOT/values-rancher-desktop.yaml"
if [[ ! -f "$VALUES_FILE" ]]; then
  VALUES_FILE="$REPO_ROOT/values-minikube.yaml"
fi

helm upgrade --install "$RELEASE" "$CHART" \
  --namespace="$NAMESPACE" \
  --create-namespace \
  -f "$VALUES_FILE" \
  --set ingress.class="$INGRESS_CLASS" \
  --wait --timeout=10m

echo ""
echo "Deployment complete!"
echo ""
echo "Access the app at: http://localhost"
echo ""
echo "Next step: initialise the database schema (first deploy only):"
echo "  kubectl run psql-init --rm -it --restart=Never --image=postgres:16 \\"
echo "    --namespace=$NAMESPACE -- psql -h postgresql -U postgres \\"
echo "    -f /dev/stdin < postgres-init/init.sql"
