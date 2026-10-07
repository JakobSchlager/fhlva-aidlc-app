## Context

`k8s-native-secrets` (archived 2026-09-02) removed Key Vault from the code and the charts, and declared `terraform-keyvault` and `keyvault-secret-bootstrap` "retired". The specs were kept with a banner. Today:

- `modules/` contains `acr`, `aks`, `network`; the dev stage calls those three. No `keyvault` module, no `set-keyvault-secrets.sh`.
- Nothing in the repository references the add-ons that existed for Key Vault: no Terraform resource uses `secret_identity` or the OIDC issuer URL (only a module output and a stage output echo it), and the charts contain no `SecretProviderClass`, CSI volume or workload-identity annotation. The charts do keep ServiceAccounts.
- `modules/aks/main.tf` still sets `oidc_issuer_enabled = true`, `workload_identity_enabled = true` and a `key_vault_secrets_provider` block with rotation `2m`.
- Terraform state is remote (`azurerm` backend); no state file is in the repository and the live cluster's configuration cannot be seen from here.

## Goals / Non-Goals

**Goals:** make the specs and the Terraform README describe what the repository actually does; remove the two retired specs; record why the OIDC issuer must not be removed.

**Non-Goals:** changing Terraform code or the live cluster; removing any AKS add-on; changing Helm charts or scripts; deciding the fate of the Secrets Store CSI add-on.

## Decisions

**D1. Delete the two retired specs by hand.**
`openspec archive` cannot remove every requirement of a spec: on a throwaway copy, a change whose delta removed all six requirements of `terraform-keyvault` passed `openspec validate` but `openspec archive` aborted with "Spec must have at least one requirement. No files were changed." That is why the earlier retirement ended as a banner. Deleting the directory with `git rm -r` is therefore a manual task in this change; the change's `MODIFIED` deltas are applied by archive as usual. Alternative: keep the banner (rejected: the specs still count as live `SHALL` statements and still appear in `openspec list --specs`, and they contradict the code). The full retired text remains in git history and in `archive/2026-09-02-k8s-native-secrets/specs/`.

**D2. The OIDC issuer stays enabled, and the spec says so.**
The Azure documentation states "You can't disable OIDC issuer once enabled" ([use-oidc-issuer](https://learn.microsoft.com/en-us/azure/aks/use-oidc-issuer), page dated 2026-07-01, accessed 2026-10-07), and the azurerm provider documents for `oidc_issuer_enabled`: "Once enabled, this feature cannot be disabled, doing so forces a new resource to be created." (the same note appears in the 4.81.0 documentation, which matches this repository's lock file, and in 5.8.0). Disabling it would therefore replace the AKS cluster: its workloads, kubelet and AGIC identities and kubeconfig all change. Workload Identity requires the OIDC issuer. The `terraform-aks` requirement is reworded to say the issuer must remain enabled and that removing it needs a deliberate, reviewed cluster-replacement decision. Unverified: what `terraform plan` shows against the real state, and whether omitting the line behaves differently per provider version (the 5.8.0 page says the default is `true`; the 4.81.0 page gives no default).

**D3. The Secrets Store CSI add-on is not removed here.**
It is the only add-on that is plausibly removable, since nothing uses it. The sources read do not say what disabling it does: Microsoft's page describes that it creates an `azurekeyvaultsecretsprovider-xxxx` managed identity in the node resource group and assigns it to the scale set, and says nothing about removal. Whether the identity is deleted or left behind, and whether the scale-set change touches the node pool, is unknown. The benefit is small (an unused add-on), so removal is left as a separate infrastructure change that someone with Azure access plans after reading a real `terraform plan`. The spec states that the add-on is enabled and currently unused.

**D4. Edit the one Purpose sentence in place.**
"Replaces `keyvault-secret-bootstrap`" in `kubernetes-secrets-bootstrap` is not a requirement, so it is edited directly, as was done for the retirement banners.

## Risks / Trade-offs

- [Someone later "cleans up" the unused add-ons and replaces the cluster] → The `terraform-aks` requirement now says the OIDC issuer must stay enabled and why; the team message mentions it.
- [Deleting the specs loses their text from `openspec/specs/`] → It remains in git and in the archived change.
- [The README rewrite points readers at the wrong place for secrets] → The replacement text points to `scripts/set-k8s-secrets.sh` and the main README, which the `kubernetes-secrets-bootstrap` spec already describes.

## Migration Plan

Docs and specs only. Rollback is `git revert`. No deployment step.

## Open Questions

- Should the Secrets Store CSI add-on be removed from `modules/aks`, and when? Needs a reviewed `terraform plan` and an owner with Azure access.
- Should the stage output `oidc_issuer_url` stay? It is harmless and costs nothing; this change keeps it.
