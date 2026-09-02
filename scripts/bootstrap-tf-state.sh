#!/usr/bin/env bash
# One-time bootstrap: creates the Azure Storage backend for Terraform state.
# Run this before `terraform init`. The storage account itself is NOT managed
# by Terraform to avoid a chicken-and-egg dependency.
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
RESOURCE_GROUP="fhooe-aidlc-tfstate-rg"
STORAGE_ACCOUNT=""        # Must be globally unique; set via --storage-account
CONTAINER="tfstate"
LOCATION="germanywestcentral"
SUBSCRIPTION=""           # Uses current az login subscription if not set

# ── Argument parsing ───────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -g, --resource-group   Resource group name (default: $RESOURCE_GROUP)
  -s, --storage-account  Storage account name (required, must be globally unique)
  -c, --container        Blob container name (default: $CONTAINER)
  -l, --location         Azure region (default: $LOCATION)
  -S, --subscription     Azure subscription ID (optional; uses current login if omitted)
  -h, --help             Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group)   RESOURCE_GROUP="$2";   shift 2 ;;
    -s|--storage-account)  STORAGE_ACCOUNT="$2";  shift 2 ;;
    -c|--container)        CONTAINER="$2";         shift 2 ;;
    -l|--location)         LOCATION="$2";          shift 2 ;;
    -S|--subscription)     SUBSCRIPTION="$2";      shift 2 ;;
    -h|--help)             usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$STORAGE_ACCOUNT" ]]; then
  echo "Error: --storage-account is required (must be globally unique, 3-24 lowercase alphanumeric)"
  usage
  exit 1
fi

# ── Optional subscription override ────────────────────────────────────────────
SUBSCRIPTION_ARGS=()
if [[ -n "$SUBSCRIPTION" ]]; then
  SUBSCRIPTION_ARGS=(--subscription "$SUBSCRIPTION")
fi

echo "==> Bootstrapping Terraform remote state"
echo "    Resource group:  $RESOURCE_GROUP"
echo "    Storage account: $STORAGE_ACCOUNT"
echo "    Container:       $CONTAINER"
echo "    Location:        $LOCATION"
echo ""

# ── Resource group ─────────────────────────────────────────────────────────────
if az group show --name "$RESOURCE_GROUP" "${SUBSCRIPTION_ARGS[@]}" &>/dev/null; then
  echo "==> Resource group '$RESOURCE_GROUP' already exists, skipping creation"
else
  echo "==> Creating resource group '$RESOURCE_GROUP'..."
  az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    "${SUBSCRIPTION_ARGS[@]}"
fi

# ── Storage account ────────────────────────────────────────────────────────────
if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" "${SUBSCRIPTION_ARGS[@]}" &>/dev/null; then
  echo "==> Storage account '$STORAGE_ACCOUNT' already exists, skipping creation"
else
  echo "==> Creating storage account '$STORAGE_ACCOUNT'..."
  az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    "${SUBSCRIPTION_ARGS[@]}"
fi

# Enable soft-delete for blobs (30-day retention)
echo "==> Enabling blob soft-delete (30 days)..."
az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --enable-delete-retention true \
  --delete-retention-days 30 \
  "${SUBSCRIPTION_ARGS[@]}"

# Enable blob versioning
echo "==> Enabling blob versioning..."
az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --enable-versioning true \
  "${SUBSCRIPTION_ARGS[@]}"

# ── Blob container ─────────────────────────────────────────────────────────────
echo "==> Creating blob container '$CONTAINER'..."
az storage container create \
  --name "$CONTAINER" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login \
  "${SUBSCRIPTION_ARGS[@]}" || true   # idempotent: ignore if already exists

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "Bootstrap complete. Run terraform init with:"
echo ""
echo "  terraform init \\"
echo "    -backend-config=\"resource_group_name=$RESOURCE_GROUP\" \\"
echo "    -backend-config=\"storage_account_name=$STORAGE_ACCOUNT\" \\"
echo "    -backend-config=\"container_name=$CONTAINER\" \\"
echo "    -backend-config=\"key=fhooe-aidlc.tfstate\""
