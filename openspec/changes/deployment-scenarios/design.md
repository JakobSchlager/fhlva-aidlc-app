## Context

The Beer Tracker application is a microservices system consisting of five containers (auth-service, beer-tracking-service, health-notification-service, statistics-service, frontend) backed by PostgreSQL. Three target deployment contexts exist:

1. **Local Compose** — developer laptop, no Kubernetes, secrets via `.env` file, PostgreSQL as a compose service.
2. **Local Minikube** — Helm-based Kubernetes deployment on a laptop, no Azure dependencies, validates chart correctness before incurring cloud costs.
3. **Azure AKS** — production-grade deployment: Bicep-provisioned infrastructure (ACR, AKS, Key Vault, PostgreSQL Flexible Server, VNet, Application Gateway, monitoring), secrets via Azure Key Vault CSI driver, images from ACR.

Current blockers for local Helm deployment: the Helm sub-chart templates hardcode Azure Secrets Store CSI volumes and `SecretProviderClass` resources, which are absent on minikube. The ingress class is fixed to `azure/application-gateway`. These must be made conditional without breaking the Azure path.

## Goals / Non-Goals

**Goals:**
- All three scenarios are independently runnable with documented prerequisites and step-by-step instructions.
- The Helm charts support both `azure` and `local` secret provider modes via a single values flag — no chart forking.
- A top-level `README.md` is the single entry point for all three scenarios.
- A `.env.example` file drives compose secret configuration.
- Two helper scripts (`scripts/deploy-minikube.sh`, `scripts/deploy-azure.sh`) automate the multi-step CLI sequences.

**Non-Goals:**
- Staging/prod environment split or GitOps (ArgoCD/Flux) — out of scope.
- Windows-native deployment (WSL2 assumed for all scenarios).
- Helm chart packaging or publishing to a Helm registry.
- Automated database migrations — schema initialisation remains a manual one-time step.

## Decisions

### Decision 1: Conditional secrets provider in Helm templates via `secretsProvider` value

**Choice:** Add `secretsProvider: azure | local` to each sub-chart's `values.yaml`. When `local`, the deployment template omits the CSI volume and volume mount; a pre-created plain Kubernetes `Secret` is referenced directly instead. The `SecretProviderClass` template is wrapped in `{{- if eq .Values.secretsProvider "azure" }}`. When `azure` (the default), behaviour is unchanged.

**Alternatives considered:**
- *Install Secrets Store CSI driver on minikube with mock provider* — requires a separate mock provider daemon, complex to maintain, and doesn't test actual Helm template structure cleanly.
- *Separate `values-local.yaml` that skips secrets entirely* — pods would crash on missing `secretKeyRef`; services still need the secret values to start.
- *Duplicate chart templates* — chart forking is a maintenance anti-pattern.

**Rationale:** A single flag keeps both paths in one chart version. The `local` path exercises almost all chart logic (deployment, service, configmap, ingress, HPA, serviceaccount) — only the CSI-specific resources are skipped.

### Decision 2: Podman Compose via the existing `docker-compose.yml`

**Choice:** Validate the existing `docker-compose.yml` for Podman Compose compatibility (Podman Compose ≥ 1.0 supports Compose spec v3). Add a note in the README about the `podman-compose` vs `podman compose` (plugin) distinction. No separate `podman-compose.yml` unless incompatibilities are found during implementation.

**Alternatives considered:**
- *New `podman-compose.yml`* — duplication risk; Compose spec is largely compatible.
- *Quadlet / systemd units* — more idiomatic for Podman but far more complex and unfamiliar to Docker-oriented developers.

**Rationale:** Minimises maintenance surface. If an incompatibility is discovered, a minimal override file (`podman-compose.override.yml`) can be added.

### Decision 3: Ingress class and TLS made values-driven

**Choice:** The umbrella chart's `ingress.yaml` template uses `{{ .Values.ingress.class }}` (already parameterised) and wraps the TLS block and AGIC annotations in a conditional on `ingress.class`. `values-minikube.yaml` sets `ingress.class: nginx` and disables TLS (minikube uses self-signed certs from the ingress addon, no explicit TLS secret needed). `values-azure.yaml` keeps `azure/application-gateway` with TLS.

**Rationale:** The ingress class value is already a chart value; only the AGIC-specific annotation and TLS block need guards.

### Decision 4: Script design — idempotent, outputs-driven

**Choice:** `scripts/deploy-azure.sh` captures Bicep deployment outputs into shell variables and passes them directly to `helm upgrade --install`. `scripts/deploy-minikube.sh` builds images into minikube's Docker daemon (`eval $(minikube docker-env)`) and creates the K8s Secrets from a sourced `.env` file. Both scripts are idempotent (safe to re-run).

**Rationale:** Avoids manual copy-paste of values between steps; makes the scripts usable in non-CI environments and as a model for the GitHub Actions workflow.

### Decision 5: Secret injection for local scenarios

**Choice:**
- Compose: secrets are environment variables in a `.env` file (gitignored). A `.env.example` is committed.
- Minikube: `scripts/deploy-minikube.sh` reads the same `.env` file and creates a `kubectl create secret generic` per service in the `beer-tracker` namespace. The K8s Secret names match what the Helm templates expect (`<release>-<chart>-secrets`).

**Rationale:** Reuses one `.env` file across both local scenarios. Developers generate local values once.

## Risks / Trade-offs

- **Chart template complexity** — Adding `{{- if eq .Values.secretsProvider "azure" }}` guards increases template complexity. Mitigation: keep the flag binary (azure/local) and document it clearly in values.yaml.
- **Sub-chart tarballs out of sync** — `charts/beer-tracker/charts/*.tgz` are pre-built tarballs. After modifying sub-chart templates, `helm dependency update` must be re-run to rebuild them. Mitigation: add this step to both deploy scripts and the README.
- **Podman Compose network naming** — Podman Compose may create networks with different names than Docker Compose, which can affect service-to-service DNS. Mitigation: use explicit network names in the compose file.
- **Minikube image availability** — Images built with `eval $(minikube docker-env)` are only available in that minikube instance; `imagePullPolicy: Never` must be set in `values-minikube.yaml` to prevent Kubernetes from trying to pull from a registry.

## Migration Plan

1. Modify sub-chart templates (conditional CSI volume, secretproviderclass).
2. Run `helm dependency update charts/beer-tracker` to rebuild tarballs.
3. Add `values-minikube.yaml` and `values-azure.yaml` at repo root.
4. Add `scripts/deploy-minikube.sh` and `scripts/deploy-azure.sh`.
5. Add `.env.example`.
6. Write `README.md`.
7. Validate compose scenario locally, then minikube scenario.
8. Commit all changes together (no phased rollout needed — purely additive).

Rollback: all changes are additive (new files + conditional template guards). Removing the new files restores the original state. The `azure` default on `secretsProvider` means existing CI/CD is unaffected.

## Open Questions

- Does the health-notification-service require an SMTP server for local testing, or is email sending gracefully skipped when unconfigured?
- Should `scripts/deploy-azure.sh` also run `openssl genpkey` to generate a fresh RSA key if `secrets/auth-rs256-private-key.pem` doesn't exist, or is that the developer's responsibility?
