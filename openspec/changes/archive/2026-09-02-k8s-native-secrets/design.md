## Context

The current secret management chain involves: a dedicated `modules/keyvault` Terraform module (~52 lines, 5 resource types), a manual bootstrap script (`set-keyvault-secrets.sh`), Helm SecretProviderClass manifests per service, Workload Identity annotations on every pod, and KV-specific Helm values (`keyVaultName`, `tenantId`, per-service `clientId`). All of this exists to deliver six largely static secrets to four application pods.

The replacement is a single Kubernetes Secret (`beer-tracker-secrets`) created before Helm deploy via one of two paths: the `deploy-azure.sh` script (automated, reads secrets from env vars) or the manual operator script (`set-k8s-secrets.sh`). Pods consume secrets as environment variables via `envFrom`.

Note: The CI/CD workflow (`ci.yml`) has been removed from the repository and is not part of this change.

## Goals / Non-Goals

**Goals:**
- Remove all Azure Key Vault Terraform resources and the runtime dependency on the KV API
- Provide a deploy-script path (`deploy-azure.sh`) and a manual operator path (`set-k8s-secrets.sh`) for secret ingestion
- Pods consume secrets as env vars — no CSI mount, no Workload Identity
- Spec retirement: `terraform-keyvault` and `keyvault-secret-bootstrap` marked retired
- Spec updates: `azure-aks-deployment` and `deployment-documentation` reflect new model

**Non-Goals:**
- Secret rotation automation (out of scope; secrets are changed infrequently)
- Encryption at rest beyond AKS default platform-managed etcd encryption
- Per-service secret scoping (all services share one K8s Secret — accepted trade-off)
- Any changes to local Compose or Minikube setups (already handle secrets independently)
- Removing Workload Identity or CSI Driver AKS addons (infra cleanup is optional, not required)
- CI/CD pipeline integration (no workflow exists in the repository)

## Decisions

### Decision 1: Single shared secret vs per-service secrets
**Choice**: One `beer-tracker-secrets` Secret in the `beer-tracker` namespace.

All six secrets (`auth-rs256-private-key`, `auth-db-password`, `tracking-db-password`, `notifications-db-password`, `statistics-db-password`, `internal-api-key`) are placed in a single K8s Secret. Each pod mounts it via `envFrom`.

**Why not per-service?** The per-service isolation in the KV design was a side-effect of the UAMI/role-assignment architecture, not an explicit requirement. For this project (small team, internal app), the operational simplicity of one secret object outweighs the marginal blast-radius benefit of splitting.

### Decision 2: envFrom vs individual secretKeyRef
**Choice**: `envFrom` referencing `beer-tracker-secrets`.

Pods inject all secrets as environment variables in one declaration. No SecretProviderClass, no CSI volume.

**Why not secretKeyRef?** Per-key refs require enumerating every secret in every pod spec — verbose and brittle when secrets are added. `envFrom` is idiomatic for this pattern and simpler to maintain.

### Decision 3: deploy-azure.sh creates the secret before Helm
**Choice**: A `kubectl create secret generic beer-tracker-secrets --from-literal=...` step runs in `scripts/deploy-azure.sh` *before* `helm upgrade --install`, using secret values from environment variables set by the operator.

**Why not a Helm hook?** Helm hooks that create Secrets complicate rollback and secret lifecycle (Helm deletes hook resources on uninstall). Managing the Secret outside Helm — created before, not owned by the release — is cleaner.

**Why not a Helm values file with secrets?** Secrets in `values.yaml` end up in the Helm release manifest stored in K8s (as a ConfigMap/Secret by Helm). Passing them via `kubectl create` keeps them out of Helm state.

### Decision 4: Manual path via set-k8s-secrets.sh
**Choice**: Replace `set-keyvault-secrets.sh` with `scripts/set-k8s-secrets.sh` that accepts `--environment dev|staging`, gets AKS credentials, and runs `kubectl create secret generic ... --dry-run=client -o yaml | kubectl apply -f -` (idempotent).

**Why `--dry-run | apply` instead of `create`?** `kubectl create secret` fails if the secret already exists. The dry-run-pipe-to-apply pattern is idempotent and consistent with the existing bootstrap script's idempotency requirement.

## Risks / Trade-offs

- **K8s Secret visibility** → Any principal with `get secret` RBAC on the `beer-tracker` namespace can read all six secrets. Mitigation: ensure namespace RBAC is appropriately restricted; AKS etcd is encrypted at rest by default with platform-managed keys.
- **No audit trail** → Unlike KV, there is no per-secret access log. Mitigation: accepted trade-off for this project; if audit trail becomes a requirement, KV or ESO+KV can be reintroduced.
- **Secret pre-existence required** → If a deploy runs before secrets are created, pods will fail to start with `CreateContainerConfigError`. Mitigation: `deploy-azure.sh` creates the secret before `helm upgrade`; for fresh clusters the manual script must be run first — documented in runbook.

## Migration Plan

1. Run `set-k8s-secrets.sh --environment dev` to create `beer-tracker-secrets` in the dev cluster before any Helm changes.
2. Apply Terraform changes (remove keyvault module) — this deletes the KV resource and UAMIs.
3. Deploy updated Helm charts (pods switch from CSI mounts to `envFrom`).
4. Verify pods start and secrets are accessible.
5. Run `deploy-azure.sh` end-to-end to verify the automated secret creation and Helm deploy path.

**Rollback**: Re-apply previous Terraform state (restores KV + UAMIs), redeploy previous Helm charts. The old bootstrap script (`set-keyvault-secrets.sh`) would need to be re-run if KV secret values were lost.

## Open Questions

- Should the Secrets Store CSI Driver and Workload Identity AKS addons be explicitly disabled in Terraform, or left enabled (no-op)? Disabling reduces attack surface but requires a cluster update.
