# Beer Tracker — Terraform Infrastructure

Terraform infrastructure for the Beer Tracker application: networking (VNet + Application Gateway), an AKS cluster, and an Azure Container Registry.

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

### Application secrets

Terraform does not manage application secrets. They live in the Kubernetes Secret `beer-tracker-secrets` (keys `auth-rs256-private-key`, `SPRING_DATASOURCE_PASSWORD` and `INTERNAL_API_KEY`), which `scripts/deploy-azure.sh` creates or updates on every deploy. To change the values without a full redeploy, run `scripts/set-k8s-secrets.sh --environment dev` (its header lists the non-interactive `SECRET_*` variables) and then `kubectl rollout restart deployment -n beer-tracker`. See the Azure AKS scenario in the main `README.md`.

## Module structure

```
infra/terraform/
├── modules/
│   ├── network/      # VNet, subnets, Application Gateway, NSG
│   ├── aks/          # AKS cluster with AGIC, Container Insights; OIDC issuer, Workload Identity and Secrets Store CSI are enabled but currently unused
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
