#!/usr/bin/env bash
# Populate the beer-tracker-secrets Kubernetes Secret.
#
# The Secret holds three keys, matching scripts/deploy-azure.sh:
#   auth-rs256-private-key      (mounted as a file by auth-service)
#   SPRING_DATASOURCE_PASSWORD  (single DB password shared by all services)
#   INTERNAL_API_KEY
#
# Prerequisites:
#   - Azure CLI logged in (az login) with access to the target subscription
#   - AKS cluster provisioned for the target environment
#   - kubectl installed on PATH
#
# Usage:
#   scripts/set-k8s-secrets.sh --environment dev
#
# The script gets AKS credentials, then prompts for each secret value
# interactively (input is hidden). To use in a non-interactive pipeline,
# set the corresponding env vars before running:
#
#   export SECRET_AUTH_RS256_PRIVATE_KEY="$(cat secrets/auth-rs256-private-key.pem)"
#   export SECRET_DB_PASSWORD="..."
#   export SECRET_INTERNAL_API_KEY="..."
#   scripts/set-k8s-secrets.sh --environment dev
set -euo pipefail

# ── Argument parsing ───────────────────────────────────────────────────────────
ENVIRONMENT=""

usage() {
  cat <<EOF
Usage: $0 --environment dev

Options:
  -e, --environment  Target environment (required: dev)
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--environment) ENVIRONMENT="$2"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$ENVIRONMENT" ]]; then
  echo "Error: --environment is required"
  usage
  exit 1
fi

case "$ENVIRONMENT" in
  dev) ;;
  *)
    echo "Error: unknown environment '$ENVIRONMENT' (must be dev)"
    usage
    exit 1
    ;;
esac

PROJECT_NAME="fhooe-aidlc"
RESOURCE_GROUP="${PROJECT_NAME}-${ENVIRONMENT}-rg"
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-aks"
NAMESPACE="beer-tracker"
SECRET_NAME="beer-tracker-secrets"

echo "==> Target: $CLUSTER_NAME ($RESOURCE_GROUP)"
echo ""

# ── Get AKS credentials ────────────────────────────────────────────────────────
echo "==> Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing

echo ""

# ── Secret reading ─────────────────────────────────────────────────────────────
read_secret() {
  local name="$1"
  local env_var="$2"
  local value

  if [[ -n "${!env_var:-}" ]]; then
    value="${!env_var}"
  else
    read -r -s -p "  Enter value for $name: " value
    echo ""
    if [[ -z "$value" ]]; then
      echo "Error: value for $name cannot be empty"
      exit 1
    fi
  fi
  echo "$value"
}

# ── Prompt for secret values ───────────────────────────────────────────────────
echo "Enter secret values (input is hidden). Press Ctrl+C to abort."
echo ""

AUTH_RS256_PRIVATE_KEY=$(read_secret "auth-rs256-private-key"    "SECRET_AUTH_RS256_PRIVATE_KEY")
DB_PASSWORD=$(read_secret             "SPRING_DATASOURCE_PASSWORD" "SECRET_DB_PASSWORD")
INTERNAL_API_KEY=$(read_secret        "INTERNAL_API_KEY"          "SECRET_INTERNAL_API_KEY")

echo ""
echo "==> Creating/updating $SECRET_NAME in namespace $NAMESPACE..."

kubectl create secret generic "$SECRET_NAME" \
  --namespace="$NAMESPACE" \
  --from-literal=auth-rs256-private-key="$AUTH_RS256_PRIVATE_KEY" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="$DB_PASSWORD" \
  --from-literal=INTERNAL_API_KEY="$INTERNAL_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Done. $SECRET_NAME is set in namespace $NAMESPACE on $CLUSTER_NAME."
