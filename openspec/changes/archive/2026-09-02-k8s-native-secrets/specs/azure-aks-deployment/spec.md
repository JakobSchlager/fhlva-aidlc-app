## MODIFIED Requirements

### Requirement: Helm deployment uses Azure values without Key Vault references
The system SHALL provide `values-azure.yaml` containing Azure-specific Helm values (ingress class). The deploy script SHALL NOT pass `keyVaultName`, `tenantId`, or per-service `clientId` values to `helm upgrade --install`. Pods SHALL read secrets from `beer-tracker-secrets` via `envFrom`.

#### Scenario: Helm release succeeds with Azure values
- **WHEN** `helm upgrade --install beer-tracker ./charts/beer-tracker -f values-azure.yaml --set ...` is run
- **THEN** the release installs without errors and all pods start, reading secrets from the `beer-tracker-secrets` Kubernetes Secret via `envFrom`

#### Scenario: Pods do not use CSI volumes or Workload Identity annotations
- **WHEN** a running Beer Tracker pod spec is inspected
- **THEN** it SHALL NOT contain SecretProviderClass volume references, CSI driver volume mounts, or `azure.workload.identity/client-id` annotations

