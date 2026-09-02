# Beer Tracker — Terraform Infrastructure

Terraform infrastructure for the Beer Tracker application: networking (VNet + Application Gateway), AKS cluster, and Key Vault with per-service managed identities.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.60
- An Azure subscription (dev and staging use separate subscriptions)
- A Log Analytics workspace already provisioned (name: `fhooe-aidlc-<env>-law`)
- A resource group already provisioned (name: `fhooe-aidlc-<env>-rg`)

## One-time setup

### 1. Fill in subscription IDs

Edit the `locals` block in each stage's `main.tf` and replace the placeholder subscription IDs:

```
infra/terraform/stages/dev/main.tf      → subscription_id = "FILL_IN_DEV_SUBSCRIPTION_ID"
infra/terraform/stages/staging/main.tf  → subscription_id = "FILL_IN_STAGING_SUBSCRIPTION_ID"
```

### 2. Create the remote state storage account

Both stages share a single storage account. Run this once before the first `terraform init`:

```bash
scripts/bootstrap-tf-state.sh \
  --resource-group  fhooe-aidlc-tfstate-rg \
  --storage-account <globally-unique-name> \
  --location        germanywestcentral
```

### 3. Fill in the storage account name

Edit `backend.tf` in each stage and replace `FILL_IN_STORAGE_ACCOUNT` with the name chosen above:

```
infra/terraform/stages/dev/backend.tf
infra/terraform/stages/staging/backend.tf
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

For staging, substitute `--environment staging` and `cd infra/terraform/stages/staging`.

## Module structure

```
infra/terraform/
├── modules/
│   ├── network/      # VNet, subnets, Application Gateway, NSG
│   ├── aks/          # AKS cluster with AGIC, Container Insights, Workload Identity
│   └── keyvault/     # Key Vault, per-service UAMIs, federated credentials, secret slots
└── stages/
    ├── dev/          # Dev environment root (backend.tf, providers.tf, main.tf, outputs.tf)
    └── staging/      # Staging environment root (same shape, staging-specific values)
```

Each stage is a self-contained Terraform root. Running `terraform` commands inside a stage targets only that environment.

## Rollback

During the migration phase the Bicep stack in the original resource group is untouched. To roll back, delete the Terraform-managed resource group:

```bash
az group delete --name fhooe-aidlc-dev-rg --yes --no-wait
```
