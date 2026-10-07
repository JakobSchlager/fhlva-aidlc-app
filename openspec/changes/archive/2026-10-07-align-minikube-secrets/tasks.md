## 1. deploy-minikube.sh

- [x] 1.1 Replace the four per-service `kubectl create secret generic` blocks with a single `beer-tracker-secrets` (keys `auth-rs256-private-key`, `SPRING_DATASOURCE_PASSWORD`, `INTERNAL_API_KEY`) from `.env`, using `--dry-run=client -o yaml | kubectl apply -f -`
- [x] 1.2 Keep Secret creation before `helm upgrade --install`; do not touch other steps
- [x] 1.3 Run `shellcheck` / `bash -n` on the script

## 2. values-minikube.yaml

- [x] 2.1 Add `AUTH_PRIVATE_KEY_PATH: "/etc/secrets/auth-rs256-private-key"` to `auth-service.env`
- [x] 2.2 Remove all `secretsProvider: local` lines

## 3. set-k8s-secrets.sh

- [x] 3.1 Reduce prompts/inputs to private key, single DB password, internal API key (`SECRET_AUTH_RS256_PRIVATE_KEY`, `SECRET_DB_PASSWORD`, `SECRET_INTERNAL_API_KEY`)
- [x] 3.2 Write the Secret with keys `auth-rs256-private-key`, `SPRING_DATASOURCE_PASSWORD`, `INTERNAL_API_KEY`
- [x] 3.3 Update header comment and usage text to the new variable names
- [x] 3.4 Run `bash -n` and exercise `--help` and the unknown-environment path

## 4. Docs and specs

- [x] 4.1 Update `README.md` secrets table and descriptions (around lines 96, 203), minikube troubleshooting (266–267) and AKS rotation/troubleshooting (452, 467), plus any mention of the six-key set
- [x] 4.2 `openspec validate align-minikube-secrets`

## 5. Verification

- [x] 5.1 Confirm `git diff` shows no changes to `scripts/deploy-azure.sh`, `charts/` or `values-azure.yaml`
- [x] 5.2 On a clean minikube run `scripts/deploy-minikube.sh`; confirm all pods reach Ready, none in `CreateContainerConfigError`
- [x] 5.3 Confirm `kubectl get secret beer-tracker-secrets -n beer-tracker` has exactly the three keys and no `*-service-secrets` exist
- [x] 5.4 Confirm auth-service finds its key at `/etc/secrets/auth-rs256-private-key`
- [x] 5.5 Confirm health-notification and statistics services connect to Postgres with `SPRING_DATASOURCE_PASSWORD` (check logs); record the outcome if relaxed binding does not apply
- [x] 5.6 Re-run the script to confirm idempotency
- [x] 5.7 Delete orphaned per-service Secrets from any existing minikube cluster
