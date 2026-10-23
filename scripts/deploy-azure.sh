#!/usr/bin/env bash
# =============================================================================
# deploy-azure.sh — Build and deploy Beer Tracker to Azure AKS
#
# Usage:
#   ./scripts/deploy-azure.sh [--help]
#
# Prerequisite: Terraform must already be applied in infra/terraform/stages/dev.
# This script reads ACR and AKS details from Terraform outputs, then builds
# and pushes images and deploys via Helm.
#
# Required environment variables (set before running):
#   AZURE_RESOURCE_GROUP    - Azure resource group name
#   POSTGRES_APP_PASSWORD   - PostgreSQL application user password
#   INTERNAL_API_KEY        - Shared internal API key
#   AUTH_RSA_KEY_PATH       - Path to RSA private key PEM file
#
# Prerequisites:
#   - az CLI logged in (az login)
#   - terraform CLI available and infra/terraform/stages/dev already applied
#   - docker or podman available (podman is Docker-CLI-compatible)
#   - kubectl and helm >= 3.10
#
# This script is idempotent — safe to re-run.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="beer-tracker"
RELEASE="beer-tracker"
CHART="$REPO_ROOT/charts/beer-tracker"
TF_DIR="$REPO_ROOT/infra/terraform/stages/dev"

# --- Help --------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,17p' "$0" | sed 's/^# \?//'
  exit 0
fi

# --- Validate required environment variables ---------------------------------
: "${AZURE_RESOURCE_GROUP:?ERROR: AZURE_RESOURCE_GROUP is not set}"
: "${POSTGRES_APP_PASSWORD:?ERROR: POSTGRES_APP_PASSWORD is not set}"
: "${INTERNAL_API_KEY:?ERROR: INTERNAL_API_KEY is not set}"
: "${AUTH_RSA_KEY_PATH:?ERROR: AUTH_RSA_KEY_PATH is not set}"

if [[ ! -f "$AUTH_RSA_KEY_PATH" ]]; then
  echo "ERROR: RSA private key not found at $AUTH_RSA_KEY_PATH" >&2
  echo "       Generate with: openssl genrsa -out secrets/auth-rs256-private-key.pem 2048" >&2
  exit 1
fi

GIT_SHA=$(git -C "$REPO_ROOT" rev-parse --short HEAD | tr -d '\r')

# --- Read infrastructure outputs from Terraform ------------------------------
echo "Reading Terraform outputs from $TF_DIR..."
ACR_LOGIN_SERVER=$(terraform -chdir="$TF_DIR" output -raw acr_login_server | tr -d '\r')
AKS_CLUSTER_NAME=$(terraform -chdir="$TF_DIR" output -raw aks_cluster_name | tr -d '\r')

echo "Terraform outputs:"
echo "  ACR: $ACR_LOGIN_SERVER"
echo "  AKS: $AKS_CLUSTER_NAME"

# --- Grant GitHub Actions SP access to AKS (if GH_SP_OBJECT_ID is set) ------
# See README Azure section for instructions on creating the service principal.
if [[ -n "${GH_SP_OBJECT_ID:-}" ]]; then
  echo "Granting GitHub Actions SP AKS RBAC access..."
  AKS_RESOURCE_ID=$(az aks show \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --query id -o tsv | tr -d '\r')
  az role assignment create \
    --assignee-object-id "$GH_SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Azure Kubernetes Service RBAC Cluster Admin" \
    --scope "$AKS_RESOURCE_ID" \
    --output none
fi

# --- Login to ACR and build/push images --------------------------------------
echo "Logging in to ACR..."
ACR_NAME="${ACR_LOGIN_SERVER%%.*}"
# Use --expose-token so login works with both Docker and Podman
ACR_TOKEN=$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query accessToken | tr -d '\r')
docker login "$ACR_LOGIN_SERVER" --username 00000000-0000-0000-0000-000000000000 --password "$ACR_TOKEN"

echo "Building and pushing images (tag: $GIT_SHA)..."
declare -A SERVICE_DIRS=(
  [auth-service]="$REPO_ROOT/services/auth-service"
  [beer-tracking-service]="$REPO_ROOT/services/beer-tracking-service"
  [health-notification-service]="$REPO_ROOT/services/health-notification-service"
  [statistics-service]="$REPO_ROOT/services/statistics-service"
  [frontend]="$REPO_ROOT/frontend"
)

for svc in "${!SERVICE_DIRS[@]}"; do
  IMAGE="$ACR_LOGIN_SERVER/$svc:$GIT_SHA"
  echo "  Building and pushing $IMAGE..."
  docker build -t "$IMAGE" "${SERVICE_DIRS[$svc]}"
  docker push "$IMAGE"
done

# --- Get AKS credentials -----------------------------------------------------
echo "Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --overwrite-existing
kubelogin convert-kubeconfig -l azurecli 2>/dev/null || true

# --- Install Bitnami PostgreSQL (idempotent) ---------------------------------
echo "Setting up PostgreSQL..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: "$NAMESPACE"
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: "$RELEASE"
    meta.helm.sh/release-namespace: "$NAMESPACE"
EOF
if ! helm status postgresql --namespace="$NAMESPACE" &>/dev/null; then
  helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
  helm repo update
  helm install postgresql bitnami/postgresql \
    --namespace="$NAMESPACE" \
    --set auth.postgresPassword="$POSTGRES_APP_PASSWORD" \
    --set auth.username=postgres \
    --wait --timeout=5m
fi

# --- Initialize databases (idempotent) ---------------------------------------
echo "Initializing databases..."
kubectl exec -i -n "$NAMESPACE" postgresql-0 -- \
  env PGPASSWORD="$POSTGRES_APP_PASSWORD" psql -U postgres \
  < "$REPO_ROOT/postgres-init/init.sql"

# --- Create beer-tracker-secrets Kubernetes Secret (idempotent) --------------
echo "Creating beer-tracker-secrets Kubernetes Secret..."
kubectl create secret generic beer-tracker-secrets \
  --namespace="$NAMESPACE" \
  --from-literal=auth-rs256-private-key="$(cat "$AUTH_RSA_KEY_PATH")" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="$POSTGRES_APP_PASSWORD" \
  --from-literal=INTERNAL_API_KEY="$INTERNAL_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Helm dependency update --------------------------------------------------
echo "Updating Helm dependencies..."
helm dependency update "$CHART"

# --- Deploy ------------------------------------------------------------------
echo "Deploying Beer Tracker to AKS..."
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace="$NAMESPACE" \
  --create-namespace \
  -f "$REPO_ROOT/values-azure.yaml" \
  --set "auth-service.image.repository=$ACR_LOGIN_SERVER/auth-service" \
  --set "auth-service.image.tag=$GIT_SHA" \
  --set "beer-tracking-service.image.repository=$ACR_LOGIN_SERVER/beer-tracking-service" \
  --set "beer-tracking-service.image.tag=$GIT_SHA" \
  --set "health-notification-service.image.repository=$ACR_LOGIN_SERVER/health-notification-service" \
  --set "health-notification-service.image.tag=$GIT_SHA" \
  --set "statistics-service.image.repository=$ACR_LOGIN_SERVER/statistics-service" \
  --set "statistics-service.image.tag=$GIT_SHA" \
  --set "frontend.image.repository=$ACR_LOGIN_SERVER/frontend" \
  --set "frontend.image.tag=$GIT_SHA" \
  --wait --timeout=10m

echo ""
echo "Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Get the ingress public IP:"
echo "   kubectl get ingress -n $NAMESPACE"
echo ""
echo "2. Initialise the PostgreSQL schema (first deploy only):"
echo "   Get the PostgreSQL FQDN: az postgres flexible-server list -g $AZURE_RESOURCE_GROUP --query '[0].fullyQualifiedDomainName' -o tsv"
echo "   psql \"host=<postgres-fqdn> port=5432 dbname=postgres user=appuser sslmode=require\" \\"
echo "     -f postgres-init/init.sql"
