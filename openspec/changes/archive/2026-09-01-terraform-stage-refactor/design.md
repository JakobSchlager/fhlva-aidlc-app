## Context

The current Terraform root at `infra/terraform/` is a single root module that serves all environments via `.tfvars` files. It has two problems:

1. **Incomplete backend**: `backend.tf` contains `PLACEHOLDER` values, so `terraform init` requires `-backend-config` flags every time.
2. **Secret variables**: Six sensitive inputs (`auth_rs256_private_key`, `*_db_password`, `internal_api_key`) and `subscription_id` must be passed via `TF_VAR_*` environment variables on every plan/apply.

The keyvault module already has `lifecycle { ignore_changes = [value] }` on all secret resources — Terraform does not reconcile secret values after initial creation. This is a half-step toward decoupling that we complete in this change.

This is a greenfield refactor: no live state exists, so no `terraform state mv` is needed.

## Goals / Non-Goals

**Goals:**
- `terraform init && terraform apply` in a stage folder requires no flags and no env vars
- Non-secret configuration (subscription ID, location, allowed IPs) is hardcoded as `locals` per stage
- Terraform creates Key Vault secret *slots* with placeholder values; real values are set by a separate bootstrap command
- Two stage folders: `stages/dev/` and `stages/staging/`, each a self-contained Terraform root
- Old flat root files are removed

**Non-Goals:**
- Production environment (future addition following the same pattern)
- Secret rotation automation (bootstrap script is a one-shot or manual step)
- State migration (no live infrastructure exists)
- Changing the modules themselves beyond the keyvault secret variable removal

## Decisions

### D1: Stage folders over Terraform workspaces

**Decision**: One directory per environment (`stages/dev/`, `stages/staging/`) rather than a single root with workspaces.

**Rationale**: Workspaces share the same backend configuration and provider setup — you still need to pass `-backend-config` or use partial config. Stage folders allow each environment to have a fully self-contained backend, providers, and locals block. This mirrors the pattern already proven in `/mnt/c/workspace/zero/infra/stages/`. Workspaces also have a footgun: running `terraform apply` in the wrong workspace silently targets the wrong environment.

**Alternative considered**: Terraform workspaces with a shared variable file per workspace — rejected because it doesn't solve the env var problem and adds workspace-switching ceremony.

---

### D2: Placeholder value in Key Vault secret slots, not empty Terraform config

**Decision**: The keyvault module keeps the six `azurerm_key_vault_secret` resources but replaces the variable-sourced `value` with a static placeholder string (`"PLACEHOLDER"`). `ignore_changes = [value]` remains.

**Rationale**: Removing the `azurerm_key_vault_secret` resources entirely means Terraform doesn't track the secret lifecycle — if someone deletes a secret manually, Terraform won't recreate it. Keeping the resource with a placeholder means Terraform creates the slot on first apply and manages its existence, while the bootstrap script owns the actual value. The existing `ignore_changes` guarantees the placeholder is never restored after the bootstrap script overwrites it.

**Alternative considered**: Remove secret resources from Terraform entirely, have the bootstrap script create them with `--if-not-exists` — rejected because it moves resource ownership out of Terraform state, making `terraform destroy` unable to clean up secrets.

---

### D3: subscription_id as hardcoded local per stage

**Decision**: `subscription_id` is a hardcoded `local` inside each stage's `main.tf`, not a variable.

**Rationale**: Dev and staging use different Azure subscriptions. Since each stage is its own Terraform root, there's no sharing conflict. Hardcoding in locals eliminates the last non-secret env var (`TF_VAR_subscription_id`) and makes the subscription for each environment immediately visible in the file — no inference needed.

**Alternative considered**: A shared `locals.tf` outside the stages that both roots include — Terraform doesn't support file includes, so this would require a wrapper module layer. Overkill for two environments.

---

### D4: Single storage account, environment-specific state keys

**Decision**: Both stages share the same Azure storage account for remote state, distinguished by key: `dev/terraform.tfstate` and `staging/terraform.tfstate`.

**Rationale**: Reduces operational overhead (one storage account to provision and manage). The risk of cross-environment state confusion is eliminated because each stage's `backend.tf` hardcodes its key. The bootstrap script provisions the storage account once.

**Alternative considered**: Separate storage accounts per environment — provides stronger blast-radius isolation but adds provisioning complexity. Can be revisited if the project adds prod with stricter isolation requirements.

## Risks / Trade-offs

**Bootstrap script must run before app deployment**
→ If someone runs `terraform apply` but forgets to run the bootstrap script, the Key Vault secrets contain `"PLACEHOLDER"` and the application will fail to start. Mitigation: document the required order clearly in the README; add a `terraform output` hint pointing to the bootstrap script.

**Different subscription IDs in hardcoded locals**
→ If a subscription ID changes (e.g. subscription migration), it requires a code change and PR rather than updating a variable. Mitigation: this is acceptable — subscription changes are infrequent and a PR provides an audit trail.

**Placeholder value visible in Terraform state**
→ The string `"PLACEHOLDER"` will appear in `terraform.tfstate` for each secret resource's initial value (before bootstrap). The real values set by the bootstrap script are not tracked in state (due to `ignore_changes`). Mitigation: acceptable — the actual sensitive values are never in state.

**Breaking change for existing callers**
→ Any CI/CD pipeline, runbook, or script that calls `terraform init -backend-config=...` or exports `TF_VAR_*` will need updating. Mitigation: documented in the README migration guide; the old flat structure is removed (no ambiguity about which root to use).

## Migration Plan

This is a greenfield refactor with no live infrastructure, so there is no state migration.

1. Remove old flat root files from `infra/terraform/` (all `.tf` files and `.tfvars` files)
2. Create `infra/terraform/stages/dev/` with `main.tf`, `backend.tf`, `providers.tf`, `outputs.tf`
3. Create `infra/terraform/stages/staging/` with the same structure and staging-specific values
4. Update `infra/terraform/modules/keyvault/` — remove secret variables, replace variable references with `"PLACEHOLDER"` string
5. Create `scripts/set-keyvault-secrets.sh`
6. Update `infra/terraform/README.md` to document the new workflow

**Rollback**: Since there is no live state, rollback is `git revert`. The old flat structure is preserved in git history.
