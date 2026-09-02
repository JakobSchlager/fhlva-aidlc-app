#!/usr/bin/env bash
# =============================================================================
# deploy-azure.sh — Deploy Beer Tracker to Azure AKS
#
# Usage:
#   ./scripts/deploy-azure.sh [--help]
#
# Required environment variables (set before running):
#   AZURE_RESOURCE_GROUP    - Azure resource group name
#   AZURE_LOCATION          - Azure region (e.g. westeurope)
#   POSTGRES_ADMIN_PASSWORD - PostgreSQL admin password
#   POSTGRES_APP_PASSWORD   - PostgreSQL application user password
#   INTERNAL_API_KEY        - Shared internal API key
#   AUTH_RSA_KEY_PATH       - Path to RSA private key PEM file
#
# Prerequisites:
#   - az CLI logged in (az login)
#   - docker available
#   - kubectl and helm >= 3.10
#
# This script is idempotent — safe to re-run.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="beer-tracker"
RELEASE="beer-tracker"
CHART="$REPO_ROOT/charts/beer-tracker"
BICEP_TEMPLATE="$REPO_ROOT/infra/main.bicep"
BICEP_PARAMS="$REPO_ROOT/infra/main.bicepparam"

# --- Help --------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,17p' "$0" | sed 's/^# \?//'
  exit 0
fi

# --- Validate required environment variables ---------------------------------
: "${AZURE_RESOURCE_GROUP:?ERROR: AZURE_RESOURCE_GROUP is not set}"
: "${AZURE_LOCATION:?ERROR: AZURE_LOCATION is not set}"
: "${POSTGRES_ADMIN_PASSWORD:?ERROR: POSTGRES_ADMIN_PASSWORD is not set}"
: "${POSTGRES_APP_PASSWORD:?ERROR: POSTGRES_APP_PASSWORD is not set}"
: "${INTERNAL_API_KEY:?ERROR: INTERNAL_API_KEY is not set}"
: "${AUTH_RSA_KEY_PATH:?ERROR: AUTH_RSA_KEY_PATH is not set}"

if [[ ! -f "$AUTH_RSA_KEY_PATH" ]]; then
  echo "ERROR: RSA private key not found at $AUTH_RSA_KEY_PATH" >&2
  echo "       Generate with: openssl genrsa -out secrets/auth-rs256-private-key.pem 2048" >&2
  exit 1
fi

GIT_SHA=$(git -C "$REPO_ROOT" rev-parse --short HEAD)

# --- Create resource group (idempotent) --------------------------------------
echo "Creating resource group $AZURE_RESOURCE_GROUP in $AZURE_LOCATION..."
az group create \
  --name "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --output none

# --- Run Bicep deployment ----------------------------------------------------
echo "Running Bicep deployment (this may take 15-20 minutes on first run)..."
DEPLOY_OUTPUT=$(az deployment group create \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --template-file "$BICEP_TEMPLATE" \
  --parameters "$BICEP_PARAMS" \
  --parameters postgresAdminPassword="$POSTGRES_ADMIN_PASSWORD" \
  --parameters postgresAppPassword="$POSTGRES_APP_PASSWORD" \
  --query "properties.outputs" \
  --output json)

# --- Capture Bicep outputs ---------------------------------------------------
ACR_LOGIN_SERVER=$(echo "$DEPLOY_OUTPUT" | jq -r '.acrLoginServer.value')
AKS_CLUSTER_NAME=$(echo "$DEPLOY_OUTPUT" | jq -r '.aksClusterName.value')
POSTGRES_FQDN=$(echo "$DEPLOY_OUTPUT" | jq -r '.postgresFqdn.value')

echo "Bicep outputs:"
echo "  ACR: $ACR_LOGIN_SERVER"
echo "  AKS: $AKS_CLUSTER_NAME"
echo "  PostgreSQL: $POSTGRES_FQDN"

# --- Grant GitHub Actions SP access to AKS (if GH_SP_OBJECT_ID is set) ------
# See README Azure section for instructions on creating the service principal.
if [[ -n "${GH_SP_OBJECT_ID:-}" ]]; then
  echo "Granting GitHub Actions SP AKS RBAC access..."
  AKS_RESOURCE_ID=$(az aks show \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --query id -o tsv)
  az role assignment create \
    --assignee-object-id "$GH_SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Azure Kubernetes Service RBAC Cluster Admin" \
    --scope "$AKS_RESOURCE_ID" \
    --output none
fi

# --- Login to ACR and build/push images --------------------------------------
echo "Logging in to ACR..."
az acr login --name "${ACR_LOGIN_SERVER%%.*}"

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

# --- Create beer-tracker-secrets Kubernetes Secret (idempotent) --------------
echo "Creating beer-tracker-secrets Kubernetes Secret..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic beer-tracker-secrets \
  --namespace="$NAMESPACE" \
  --from-literal=auth-rs256-private-key="$(cat "$AUTH_RSA_KEY_PATH")" \
  --from-literal=auth-db-password="$POSTGRES_APP_PASSWORD" \
  --from-literal=tracking-db-password="$POSTGRES_APP_PASSWORD" \
  --from-literal=notifications-db-password="$POSTGRES_APP_PASSWORD" \
  --from-literal=statistics-db-password="$POSTGRES_APP_PASSWORD" \
  --from-literal=internal-api-key="$INTERNAL_API_KEY" \
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
echo "   psql \"host=$POSTGRES_FQDN port=5432 dbname=postgres user=appuser sslmode=require\" \\"
echo "     -f postgres-init/init.sql"
