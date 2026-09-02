## Status: RETIRED

Replaced by `kubernetes-secrets-bootstrap`. The `set-keyvault-secrets.sh` script and the Azure Key Vault secret bootstrapping workflow have been removed. Secret bootstrapping is now handled by `scripts/set-k8s-secrets.sh` (see `kubernetes-secrets-bootstrap` spec).

## Purpose

Specifies requirements for `scripts/set-keyvault-secrets.sh`, which populates Azure Key Vault secret values after Terraform has provisioned the vault infrastructure. This script is the exclusive owner of secret content; Terraform creates only placeholder slots.

## Requirements

### Requirement: Bootstrap script sets all six Key Vault secrets
`scripts/set-keyvault-secrets.sh` SHALL accept an `--environment` flag (values: `dev`, `staging`) and populate all six secrets in the corresponding Key Vault using `az keyvault secret set`. The six secrets are: `auth-rs256-private-key`, `auth-db-password`, `tracking-db-password`, `notifications-db-password`, `statistics-db-password`, `internal-api-key`.

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
Running the bootstrap script multiple times SHALL not cause errors. Each `az keyvault secret set` call SHALL succeed whether the secret already exists or not, overwriting the previous value.

#### Scenario: Script is re-run after initial bootstrap
- **WHEN** the script is run a second time for the same environment
- **THEN** it SHALL succeed without errors and update all six secret values

### Requirement: Script usage documentation
The script SHALL include a usage comment block at the top explaining the prerequisites (Azure CLI logged in, Key Vault already provisioned by Terraform), the `--environment` flag, and example invocations for both environments.

#### Scenario: Usage is visible without running the script
- **WHEN** a user reads the script file or runs it with `--help`
- **THEN** prerequisites, flag descriptions, and example invocations SHALL be visible
