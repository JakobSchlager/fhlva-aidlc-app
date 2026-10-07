## 1. Retired specs

- [x] 1.1 `git rm -r openspec/specs/keyvault-secret-bootstrap openspec/specs/terraform-keyvault` (manual: archive cannot delete a spec, see design D1) (done with a plain `rm -r`, not `git rm`, so the deletion stays out of the index that holds the devcontainer commit; stage it with the commit of this change)
- [x] 1.2 In `openspec/specs/kubernetes-secrets-bootstrap/spec.md` Purpose, reword "Replaces `keyvault-secret-bootstrap`." so it does not point at a spec that no longer exists (for example "Replaces the retired Key Vault bootstrap, see the archived change `k8s-native-secrets`.")
- [x] 1.3 Confirm no other file refers to the two spec names outside `openspec/changes/archive/` (none found outside the archive and this change)

## 2. Terraform README

- [x] 2.1 `infra/terraform/README.md` line 3: remove "and Key Vault with per-service managed identities" from the one-line description
- [x] 2.2 Remove the section "Set secret values (after first apply)" (it runs `scripts/set-keyvault-secrets.sh`, which no longer exists) and replace it with a pointer to `scripts/set-k8s-secrets.sh --environment dev` and the secrets section of the main `README.md`
- [x] 2.3 In the module tree, delete the `keyvault/` entry and change the `aks/` comment so it no longer implies a Key Vault dependency
- [x] 2.4 Re-read the whole file for any other statement that depends on Key Vault (the "Rollback" section included) (no other Key Vault, identity or secret-slot wording left in the file; separate, out of scope: line 20 says `FILL_IN_DEV_SUBSCRIPTION_ID` while `stages/dev/main.tf` has `FILL_IN_STAGING_SUBSCRIPTION_ID`)

## 3. Verify

- [x] 3.1 `openspec validate retire-keyvault-specs` and `openspec validate --specs` pass; `openspec list --specs` shows 15 specs (17 minus the two removed; done, validation passes)
- [x] 3.2 `grep -rniE "key ?vault|keyvault"` over `openspec/specs`, `infra/terraform/README.md` and `infra/terraform/modules` finds only statements that Key Vault is **not** used, and the `key_vault_secrets_provider` block in `modules/aks` (verified after the sync, 2026-10-07: the remaining hits are the negations in `azure-aks-deployment`, `deployment-documentation`, `kubernetes-secrets-bootstrap` and `local-minikube-deployment`, the Secrets Store CSI add-on wording in `terraform-aks`, and the `key_vault_secrets_provider` block in `modules/aks`)
- [x] 3.3 `git diff --stat -- 'infra/**/*.tf' charts scripts` is empty: no Terraform, chart or script change (no `.tf`, chart, script or values change)
- [x] 3.4 Archive the change (`openspec archive retire-keyvault-specs`) so the three modified specs are updated, then confirm `openspec validate --specs` still passes (archived 2026-10-07 with sync: 3 specs updated, 5 requirements modified, 0 added or removed; `openspec validate --all` passes with 15 specs)

## 4. Follow-up, not part of this change

- [ ] 4.1 Someone with Azure access decides whether to remove the Secrets Store CSI add-on (`key_vault_secrets_provider`) from `modules/aks`, after reading a real `terraform plan` (design D3). **Do not** remove `oidc_issuer_enabled`: it forces cluster replacement (design D2)
