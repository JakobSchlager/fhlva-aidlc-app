## REMOVED Requirements

### Requirement: Bootstrap script sets all six Key Vault secrets
**Reason**: `scripts/set-keyvault-secrets.sh` is removed. Secret bootstrapping is now handled by `scripts/set-k8s-secrets.sh` (Kubernetes Secret) and the CI/CD pipeline. See the `kubernetes-secrets-bootstrap` capability.
**Migration**: Delete `scripts/set-keyvault-secrets.sh`. Use `scripts/set-k8s-secrets.sh --environment <env>` for manual secret setup.

#### Scenario: Script accepts --environment flag
- **WHEN** the script is invoked with `--environment dev`
- **THEN** it SHALL target the Key Vault named `beertracker-dev-kv` and set all six secrets

#### Scenario: Script rejects unknown environments
- **WHEN** the script is invoked with an unrecognised `--environment` value
- **THEN** it SHALL exit with a non-zero status and print a usage error

#### Scenario: Script prompts or accepts secrets interactively or via stdin
- **WHEN** the script is run interactively
- **THEN** it SHALL prompt the operator for each secret value, or support piping values from a secrets manager output

### Requirement: Script is idempotent
**Reason**: Removed along with the script. The replacement script (`set-k8s-secrets.sh`) carries an equivalent idempotency requirement.
**Migration**: None — idempotency is covered by `kubernetes-secrets-bootstrap`.

#### Scenario: Script is re-run after initial bootstrap
- **WHEN** the script is run a second time for the same environment
- **THEN** it SHALL succeed without errors and update all six secret values

### Requirement: Script usage documentation
**Reason**: Removed along with the script. Replacement is documented in `scripts/set-k8s-secrets.sh` and the updated README.
**Migration**: Update deployment documentation to reference `set-k8s-secrets.sh`.

#### Scenario: Usage is visible without running the script
- **WHEN** a user reads the script file or runs it with `--help`
- **THEN** prerequisites, flag descriptions, and example invocations SHALL be visible
