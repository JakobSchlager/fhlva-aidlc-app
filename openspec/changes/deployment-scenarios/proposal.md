## Why

The Beer Tracker application currently has no documented or standardised deployment process. Developers need a local workflow for fast iteration, a Kubernetes-native path for validating Helm chart behaviour before cloud costs are incurred, and a production-grade Azure pipeline that mirrors what CI/CD will eventually run automatically.

## What Changes

- Add a `podman-compose.yml` (or confirm/adapt the existing `docker-compose.yml` for Podman) with all services, PostgreSQL, and the nginx reverse-proxy wired together for local development.
- Add a `values-minikube.yaml` Helm values override and patch the sub-chart templates to make the Azure-specific CSI/Key Vault and workload-identity blocks conditional, so the umbrella chart deploys cleanly on minikube with plain Kubernetes Secrets.
- Add a `values-azure.yaml` Helm values file and a step-by-step Bicep + Helm deployment script (`scripts/deploy-azure.sh`) for the AKS production path.
- Add a top-level `README.md` (and optionally per-scenario docs under `docs/`) documenting prerequisites, configuration, and runbook steps for each of the three deployment scenarios.

## Capabilities

### New Capabilities

- `local-compose-deployment`: Run the full application stack locally using Podman Compose (or Docker Compose), covering service wiring, Postgres initialisation, secret injection via `.env`, and nginx routing.
- `local-minikube-deployment`: Deploy the Helm umbrella chart to a local minikube cluster without any Azure dependencies, using a `values-minikube.yaml` override, plain Kubernetes Secrets, and the minikube nginx ingress addon.
- `azure-aks-deployment`: End-to-end deployment to Azure — Bicep infrastructure provisioning (ACR, AKS, Key Vault, PostgreSQL, VNet, monitoring) followed by image build/push and Helm release to AKS — documented as a CLI runbook and as the reference for the GitHub Actions CI/CD pipeline.
- `deployment-documentation`: A `README.md` at the project root covering all three scenarios with prerequisites, step-by-step instructions, configuration reference, and troubleshooting notes.

### Modified Capabilities

- `user-auth`: No requirement changes — the auth-service secret (RSA private key) is now injected via three different mechanisms depending on scenario (`.env` file / K8s Secret / Azure Key Vault CSI), but the service contract is unchanged.

## Impact

- **Charts**: `charts/*/templates/deployment.yaml` and `charts/*/templates/secretproviderclass.yaml` gain conditional logic around the CSI volume and `SecretProviderClass` resources.
- **Compose file**: `docker-compose.yml` is validated for Podman compatibility or a `podman-compose.yml` is added alongside it.
- **New files**: `values-minikube.yaml`, `values-azure.yaml`, `scripts/deploy-azure.sh`, `scripts/deploy-minikube.sh`, `README.md`.
- **Secrets handling**: A `.env.example` file is added for local compose; existing `secrets/README.md` is updated to reference it.
- **No API or data-model changes** to any service.
