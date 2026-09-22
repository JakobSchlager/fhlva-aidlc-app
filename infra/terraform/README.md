# Beer Tracker — Terraform Infrastructure

Terraform infrastructure for the Beer Tracker application: networking (VNet + Application Gateway), AKS cluster, and Key Vault with per-service managed identities.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.60
- An Azure subscription
- A Log Analytics workspace already provisioned (name: `fhooe-aidlc-<env>-law`)
- A resource group already provisioned (name: `fhooe-aidlc-<env>-rg`)

## One-time setup

### 1. Fill in the subscription ID

Edit the `locals` block in `stages/dev/main.tf` and replace the placeholder subscription ID:

```
infra/terraform/stages/dev/main.tf  →  subscription_id = "FILL_IN_DEV_SUBSCRIPTION_ID"
```

### 2. Create the remote state storage account

Run this once before the first `terraform init`:

```bash
scripts/bootstrap-tf-state.sh \
  --resource-group  fhooe-aidlc-tfstate-rg \
  --storage-account <globally-unique-name> \
  --location        germanywestcentral
```

### 3. Fill in the storage account name

Edit `backend.tf` and replace `FILL_IN_STORAGE_ACCOUNT` with the name chosen above:

```
infra/terraform/stages/dev/backend.tf
```

## Deploying an environment

### Init (first time or after backend change)

```bash
cd infra/terraform/stages/dev
terraform init
```

No flags required — the backend is fully specified in `backend.tf`.

### Plan and apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

No environment variables required.

### Set secret values (after first apply)

Terraform creates Key Vault secret slots with a placeholder value. Run the bootstrap script to set real values:

```bash
# Interactive — prompts for each secret
scripts/set-keyvault-secrets.sh --environment dev

# Non-interactive (CI/CD pipeline)
export SECRET_AUTH_RS256_PRIVATE_KEY="$(cat secrets/auth.pem)"
export SECRET_AUTH_DB_PASSWORD="..."
export SECRET_TRACKING_DB_PASSWORD="..."
export SECRET_NOTIFICATIONS_DB_PASSWORD="..."
export SECRET_STATISTICS_DB_PASSWORD="..."
export SECRET_INTERNAL_API_KEY="..."
scripts/set-keyvault-secrets.sh --environment dev
```

The script is idempotent — re-running it updates the values. Subsequent `terraform apply` runs do not overwrite secrets (enforced by `lifecycle { ignore_changes = [value] }`).

## Module structure

```
infra/terraform/
├── modules/
│   ├── network/      # VNet, subnets, Application Gateway, NSG
│   ├── aks/          # AKS cluster with AGIC, Container Insights, Workload Identity
│   ├── keyvault/     # Key Vault, per-service UAMIs, federated credentials, secret slots
│   └── acr/          # Azure Container Registry (Standard SKU); kubelet identity granted AcrPull in each stage
└── stages/
    └── dev/          # Dev environment root (backend.tf, providers.tf, main.tf, outputs.tf)
```

The stage is a self-contained Terraform root. Running `terraform` commands inside `stages/dev/` targets only that environment.

## Rollback

To tear down all Terraform-managed resources, delete the resource group:

```bash
az group delete --name fhooe-aidlc-dev-rg --yes --no-wait
```
