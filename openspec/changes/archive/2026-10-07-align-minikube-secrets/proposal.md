## Why

`scripts/deploy-minikube.sh` creates four per-service Secrets (`beer-tracker-<service>-secrets`), but every Helm chart consumes a single `beer-tracker-secrets` via `envFrom`. The Secret never exists on minikube, so all pods stay in `CreateContainerConfigError`. Even if it did, the dashed keys (`auth-db-password`, `internal-api-key`, ...) are not valid environment variable names and `envFrom` would skip them; the services read `SPRING_DATASOURCE_PASSWORD` and `INTERNAL_API_KEY`. `scripts/set-k8s-secrets.sh` has the same dashed six-key set and likewise does not match what `deploy-azure.sh` (working, and frozen) creates. The charts were moved to the shared-secret model in `k8s-native-secrets` (2026-09-02), but minikube, `set-k8s-secrets.sh`, two main specs and the README were never updated.

## What Changes

- `scripts/deploy-minikube.sh`: replace the four per-service Secrets with one `beer-tracker-secrets` containing `auth-rs256-private-key`, `SPRING_DATASOURCE_PASSWORD` and `INTERNAL_API_KEY`, sourced from `.env` (`POSTGRES_PASSWORD`, `INTERNAL_API_KEY`, RSA key file). Idempotent via `--dry-run=client -o yaml | kubectl apply -f -`.
- `scripts/set-k8s-secrets.sh`: change the key set to the same three keys with a single DB password. **BREAKING** for operators using the `SECRET_AUTH_DB_PASSWORD`, `SECRET_TRACKING_DB_PASSWORD`, `SECRET_NOTIFICATIONS_DB_PASSWORD` and `SECRET_STATISTICS_DB_PASSWORD` env vars: they are replaced by a single DB password variable.
- `values-minikube.yaml`: add `AUTH_PRIVATE_KEY_PATH: /etc/secrets/auth-rs256-private-key` for auth-service; remove the dead `secretsProvider: local` entries (no chart reads them).
- Secret-creation snippets stay duplicated between `deploy-minikube.sh` and `deploy-azure.sh` (decided; no shared helper).
- Update `README.md` (secret table and minikube/AKS descriptions and troubleshooting) and the affected main specs.
- Verify on a real minikube cluster that all pods reach Ready, including that `SPRING_DATASOURCE_*` overrides `DB_*` in health-notification-service and statistics-service.
- **Not changed:** `scripts/deploy-azure.sh`, `charts/`, `values-azure.yaml`. The Azure deployment works and must stay untouched.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `local-minikube-deployment`: remove the `secretsProvider` flag requirement and the per-service `<release>-<chart>-secrets` requirement; replace with a shared `beer-tracker-secrets` requirement; update the deploy-script requirement and add `AUTH_PRIVATE_KEY_PATH` to the values requirement.
- `kubernetes-secrets-bootstrap`: the key set changes from six dashed keys to the three keys actually consumed (`auth-rs256-private-key`, `SPRING_DATASOURCE_PASSWORD`, `INTERNAL_API_KEY`); `set-k8s-secrets.sh` prompts for a single DB password; add `deploy-minikube.sh` as a creator of the secret.

## Impact

- Code: `scripts/deploy-minikube.sh`, `scripts/set-k8s-secrets.sh`, `values-minikube.yaml`.
- Docs/specs: `README.md`, `openspec/specs/local-minikube-deployment/spec.md`, `openspec/specs/kubernetes-secrets-bootstrap/spec.md`.
- Operators: anyone with automation setting the four `SECRET_*_DB_PASSWORD` variables must switch to the single variable. The Azure deploy path and CI are unaffected.
- Independent of the in-progress `add-podman-devcontainer` change.
