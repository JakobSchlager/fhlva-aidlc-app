## Why

The `k8s-native-secrets` change (2026-09-02) replaced Azure Key Vault with a Kubernetes Secret and deleted the `modules/keyvault` module and `scripts/set-keyvault-secrets.sh`. Its specs were only half retired: `keyvault-secret-bootstrap` and `terraform-keyvault` still carry every `SHALL` requirement under a hand-written "Status: RETIRED" banner, because `openspec archive` refuses to leave a spec with zero requirements (tested on a copy: "Spec must have at least one requirement. No files were changed."). Meanwhile three live specs and `infra/terraform/README.md` still describe the removed Key Vault design, and the README tells operators to run a script that no longer exists.

## What Changes

- **Delete** the spec directories `openspec/specs/keyvault-secret-bootstrap/` and `openspec/specs/terraform-keyvault/`. This cannot be expressed as a delta, so it is a manual task. History stays in git and in the archived change `2026-09-02-k8s-native-secrets`, whose deltas hold the full retired text.
- **Modify** `terraform-stage-dev` (the dev stage calls `network`, `aks` and `acr`, not `keyvault`), `terraform-network` (outputs are consumed by `aks`, not `keyvault`) and `terraform-aks` (the OIDC issuer, Workload Identity and Secrets Store CSI add-ons are enabled but currently unused; the OIDC issuer must stay enabled).
- **Fix** `infra/terraform/README.md`: remove the Key Vault description, the "Set secret values" section that calls the deleted script, and the `keyvault/` entry of the module tree.
- **Reword** the "Replaces `keyvault-secret-bootstrap`" sentence in the `kubernetes-secrets-bootstrap` Purpose, which would otherwise point at a spec that no longer exists.
- **Not changed:** any Terraform code, the live cluster, and any Helm chart. The AKS add-ons stay as they are (see design).

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `terraform-stage-dev`: the "Dev stage calls all root modules" requirement no longer lists the `keyvault` module.
- `terraform-network`: the "Module outputs for downstream consumers" requirement no longer names the `keyvault` module as a consumer.
- `terraform-aks`: the Workload Identity / OIDC, add-on and outputs requirements stop referring to the Key Vault module and state that the add-ons are currently unused; the OIDC issuer is required to stay enabled.

### Removed Capabilities (manual, not a delta)
- `keyvault-secret-bootstrap`, `terraform-keyvault`: retired in `k8s-native-secrets`, now deleted.

## Impact

- Specs: two directories removed (17 specs become 15, counting `devcontainer-environment` from the archived devcontainer change), three modified, one Purpose sentence edited.
- Docs: `infra/terraform/README.md`.
- No runtime, Terraform or Helm change. `terraform plan` output is unaffected.
- Independent of the devcontainer change (`add-podman-devcontainer`, already archived); commit separately.
