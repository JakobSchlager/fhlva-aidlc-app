## 1. Helm Chart — Conditional Secrets Provider

- [x] 1.1 Add `secretsProvider: azure` default to each sub-chart's `values.yaml` (auth-service, beer-tracking-service, health-notification-service, statistics-service, frontend)
- [x] 1.2 Wrap the `SecretProviderClass` template in each sub-chart with `{{- if eq .Values.secretsProvider "azure" }}` … `{{- end }}`
- [x] 1.3 Make the CSI `secrets-store` volume in each sub-chart's `deployment.yaml` conditional on `secretsProvider == "azure"`
- [x] 1.4 Make the CSI `volumeMount` in each sub-chart's `deployment.yaml` conditional on `secretsProvider == "azure"`
- [x] 1.5 For the `auth-service` sub-chart: when `secretsProvider == "local"`, set `AUTH_PRIVATE_KEY_PATH` to `/mnt/secrets-store/auth-rs256-private-key` sourced from the plain K8s Secret volume mount instead of CSI
- [x] 1.6 Wrap the AGIC-specific annotation (`appgw.ingress.kubernetes.io/ssl-redirect`) in `charts/beer-tracker/templates/ingress.yaml` in a conditional on `ingress.class == "azure/application-gateway"`
- [x] 1.7 Make the `tls` block in `ingress.yaml` conditional (disabled when `ingress.tls.enabled` is false)
- [x] 1.8 Run `helm dependency update charts/beer-tracker` to rebuild sub-chart tarballs and commit the updated `charts/beer-tracker/charts/*.tgz`
- [x] 1.9 Run `helm template beer-tracker ./charts/beer-tracker -f values-minikube.yaml` and verify no `SecretProviderClass` or CSI volume appears in the output

## 2. Helm Values Files

- [x] 2.1 Create `values-minikube.yaml` at repo root: set `secretsProvider: local`, `imagePullPolicy: Never`, `ingress.class: nginx`, `ingress.tls.enabled: false`, and placeholder image names for all five services
- [x] 2.2 Create `values-azure.yaml` at repo root: set `secretsProvider: azure`, `ingress.class: azure/application-gateway`, `ingress.tls.enabled: true` — all other values supplied at deploy time via `--set`

## 3. Compose — Podman Compatibility

- [x] 3.1 Review `docker-compose.yml` against Podman Compose ≥ 1.0 compatibility checklist (network aliases, healthcheck syntax, volume bind-mount syntax)
- [x] 3.2 Resolve any incompatibilities found (update `docker-compose.yml` in place or add a `podman-compose.override.yml` if needed)
- [x] 3.3 Ensure the RSA private key is bind-mounted into auth-service from `./secrets/auth-rs256-private-key.pem`
- [x] 3.4 Verify postgres init SQL (`postgres-init/init.sql`) is mounted and executed on first container start
- [x] 3.5 Create `.env.example` at repo root with all required variables (DB passwords, internal API key, RSA key path) and inline comments explaining each

## 4. Deploy Scripts

- [x] 4.1 Create `scripts/deploy-minikube.sh`: check minikube is running; enable ingress addon; eval minikube docker-env; build all five images; source `.env`; create K8s Secrets per service; run `helm dependency update`; run `helm upgrade --install` with `values-minikube.yaml`
- [x] 4.2 Create `scripts/deploy-azure.sh`: create resource group; run Bicep deployment; capture outputs; az acr login; build and push images tagged with git SHA; az aks get-credentials; run `helm dependency update`; run `helm upgrade --install` with `values-azure.yaml` and all `--set` flags from Bicep outputs
- [x] 4.3 Make both scripts executable (`chmod +x`) and add a usage/help block at the top of each
- [x] 4.4 Add a guard in `deploy-azure.sh` that exits with an error if any required environment variable (passwords, RSA key path) is unset
- [x] 4.5 After the Bicep deployment, grant the GitHub Actions service principal the `Azure Kubernetes Service RBAC Cluster Admin` role on the AKS cluster resource, so it can call `az aks get-credentials` without local account credentials (document this step in the README Azure section)

## 5. PostgreSQL — Minikube In-Cluster

- [x] 5.1 Add a PostgreSQL deployment to the minikube setup: either a minimal `postgres:16` Deployment + Service in the umbrella chart (behind a `postgres.enabled` flag) or document `helm install postgresql bitnami/postgresql` as a prerequisite step
- [x] 5.2 Document the one-time step of running `postgres-init/init.sql` against the in-cluster PostgreSQL after first deploy (via `kubectl exec` or port-forward + psql)

## 6. Documentation — README.md

- [x] 6.1 Create `README.md` at repo root with: project overview, architecture section (five services + roles), and a table of contents linking to each scenario
- [x] 6.2 Write the **Scenario 1 — Podman Compose** section: prerequisites (Podman ≥ 4, Podman Compose ≥ 1.0 or Docker Compose v2), setup steps (generate RSA key, copy `.env.example` to `.env`, fill values, `podman compose up -d`), verification (`curl http://localhost:8080`), and troubleshooting (port conflicts, missing key file, DB init failures)
- [x] 6.3 Write the **Scenario 2 — minikube** section: prerequisites (minikube, kubectl, helm ≥ 3.10), setup steps (start minikube, run `scripts/deploy-minikube.sh`, add minikube IP to `/etc/hosts` if needed), verification (`kubectl get pods -n beer-tracker`), and troubleshooting (ImagePullBackOff, missing secrets, ingress not routing)
- [x] 6.4 Write the **Scenario 3 — Azure AKS** section: prerequisites (az CLI, docker, kubectl, helm), setup steps (create SP, set env vars, run `scripts/deploy-azure.sh`, initialise DB schema, set GitHub Actions secrets), verification (`kubectl get pods -n beer-tracker`, check ingress public IP), and troubleshooting (CSI driver failures, Key Vault access denied, Bicep deployment errors)
- [x] 6.5 Write the **Troubleshooting** section covering cross-scenario issues: port 8080 conflict, RSA key generation command, health probe startup delays, database connection failures
- [x] 6.6 Update `secrets/README.md` to reference `.env.example` and clarify that the same RSA key is used across all three scenarios

## 7. Validation

- [ ] 7.1 Run `podman compose up -d` (or `docker compose up -d`) and verify all containers reach healthy state
- [ ] 7.2 Run `scripts/deploy-minikube.sh` against a clean minikube instance and verify all pods reach `Running`
- [x] 7.3 Run `helm template beer-tracker ./charts/beer-tracker -f values-azure.yaml` and verify CSI volume and `SecretProviderClass` are present in the output
- [x] 7.4 Commit `.github/workflows/ci.yml` and `infra/` (currently untracked) alongside all new files in a single commit
