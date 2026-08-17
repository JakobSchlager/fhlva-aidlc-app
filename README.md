# Beer Tracker

A microservices application for tracking beer consumption with health threshold monitoring and notifications. Users log drinks via a React frontend; backend services record events, evaluate consumption against configurable thresholds, aggregate statistics, and issue JWT-authenticated API calls between services.

## Table of Contents

- [Architecture](#architecture)
- [Configuration Reference](#configuration-reference)
- [Scenario 1 — Podman Compose / Docker Compose](#scenario-1--podman-compose--docker-compose)
- [Scenario 2 — minikube](#scenario-2--minikube)
- [Scenario 3 — Azure AKS](#scenario-3--azure-aks)
- [Troubleshooting](#troubleshooting)

---

## Architecture

### Services

| Service | Port | Description | Database |
|---|---|---|---|
| `auth-service` | 8081 | Issues and validates JWTs using RSA-256. Exposes JWKS endpoint for token verification. | `auth_db` |
| `beer-tracking-service` | 8082 | Records beer consumption events. Validates JWTs via JWKS. | `tracking_db` |
| `health-notification-service` | 8083 | Evaluates consumption against daily/weekly thresholds; sends notifications when exceeded. | `notifications_db` |
| `statistics-service` | 8084 | Aggregates consumption data for analysis and reporting. | `statistics_db` |
| `frontend` | 80 | React/Vite SPA served as static files. | — |

All five services sit behind an **nginx reverse proxy** (compose) or a **Kubernetes ingress controller** (minikube/AKS), which routes requests to the correct upstream based on URL path.

### Data layer

A single PostgreSQL 16 instance (compose) or a Bitnami PostgreSQL chart / Azure PostgreSQL Flexible Server (Kubernetes) hosts all four databases. Schema is initialised from `postgres-init/init.sql`.

### RSA key flow

`auth-service` loads an RSA-256 private key at startup and uses it to sign JWTs. The matching public key is published at `/auth/.well-known/jwks.json`. All other services fetch that JWKS endpoint on startup and cache it for token verification. No other service ever sees the private key.

| Scenario | Key delivery mechanism |
|---|---|
| Compose | `secrets/auth-rs256-private-key.pem` bind-mounted read-only into the container |
| minikube | `deploy-minikube.sh` reads `.env` → `kubectl create secret generic` → pod consumes via `secretKeyRef` |
| Azure AKS | `deploy-azure.sh` uploads key to Azure Key Vault → CSI driver mounts it into the pod |

---

## Configuration Reference

| Variable | Used by | Description |
|---|---|---|
| `POSTGRES_PASSWORD` | All Spring services, postgres | Password for the `postgres` superuser |
| `INTERNAL_API_KEY` | All Spring services | Shared secret for service-to-service calls |
| `AUTH_PRIVATE_KEY_PATH` | `auth-service` | Filesystem path to RSA-256 private key PEM |
| `JWKS_URI` | `beer-tracking-service`, `health-notification-service`, `statistics-service` | URL of the JWKS endpoint on `auth-service` |
| `BEER_TRACKING_INTERNAL_URL` | `health-notification-service`, `statistics-service` | Base URL of `beer-tracking-service` for internal calls |
| `THRESHOLD_DAILY_DRINKS` | `health-notification-service` | Daily drink count that triggers a notification |
| `THRESHOLD_WEEKLY_DRINKS` | `health-notification-service` | Weekly drink count that triggers a notification |
| `VITE_API_BASE_URL` | `frontend` (build-time) | Base URL the browser uses to reach the API |

Copy `.env.example` to `.env` and fill in values before running any scenario. See `secrets/README.md` for key generation instructions.

---

## Scenario 1 — Podman Compose / Docker Compose

Runs the full stack on your laptop. nginx listens on `localhost:8080`.

### Prerequisites

- **Podman ≥ 4** + **Podman Compose ≥ 1.0**, **or** Docker + Docker Compose v2 (`docker compose` subcommand)
- `openssl` available on `$PATH`

### Setup

1. Generate the RSA private key:

   ```bash
   openssl genrsa -out secrets/auth-rs256-private-key.pem 2048
   ```

2. Create your local environment file:

   ```bash
   cp .env.example .env
   # Edit .env and set POSTGRES_PASSWORD and INTERNAL_API_KEY
   ```

3. Start the stack:

   ```bash
   # Podman
   podman compose up -d

   # Docker
   docker compose up -d
   ```

### Verification

```bash
curl http://localhost:8080
```

The frontend HTML should be returned. Individual service health endpoints are available on their direct ports (e.g. `curl http://localhost:8081/actuator/health`).

### Troubleshooting

| Symptom | Resolution |
|---|---|
| `address already in use :8080` | Find the conflicting process: `lsof -i :8080`. Change the host port in `docker-compose.yml` if needed. |
| `auth-service` exits at startup | Verify `secrets/auth-rs256-private-key.pem` exists and is readable. Re-run step 1. |
| `postgres` health check fails | First-time volume init can be slow. Run `podman compose logs postgres` and wait for `database system is ready`. |
| Services fail with `Connection refused` to postgres | Ensure the `depends_on` health check is satisfied. Check that `POSTGRES_PASSWORD` in `.env` matches what postgres was initialised with. |

---

## Scenario 2 — minikube

Deploys the Helm umbrella chart to a local minikube cluster. Useful for validating chart changes before pushing to Azure.

### Prerequisites

- **minikube ≥ 1.32**
- **kubectl**
- **helm ≥ 3.10**
- `.env` file created from `.env.example` (same file as Scenario 1)

### Setup

1. Start minikube:

   ```bash
   minikube start
   ```

2. Create `.env` from `.env.example` if you have not already:

   ```bash
   cp .env.example .env
   # Edit .env: set POSTGRES_PASSWORD, INTERNAL_API_KEY, AUTH_RSA_KEY_PATH
   ```

3. Deploy:

   ```bash
   ./scripts/deploy-minikube.sh
   ```

   The script reads `.env`, creates the `beer-tracker` namespace, creates a `kubectl create secret generic` with all required values, builds images into the minikube Docker daemon, and runs `helm upgrade --install`.

4. Expose the ingress (if needed):

   ```bash
   minikube addons enable ingress
   echo "$(minikube ip)  beer-tracker.local" | sudo tee -a /etc/hosts
   ```

### One-time database initialisation

After the first deploy, run `postgres-init/init.sql` against the in-cluster PostgreSQL pod:

```bash
# Wait for PostgreSQL pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql \
  -n beer-tracker --timeout=120s

# Copy the init SQL into the PostgreSQL pod and run it
kubectl cp postgres-init/init.sql beer-tracker/$(kubectl get pod \
  -l app.kubernetes.io/name=postgresql -n beer-tracker \
  -o jsonpath='{.items[0].metadata.name}'):/tmp/init.sql \
  -n beer-tracker

kubectl exec -n beer-tracker \
  $(kubectl get pod -l app.kubernetes.io/name=postgresql \
    -n beer-tracker -o jsonpath='{.items[0].metadata.name}') -- \
  psql -U postgres -f /tmp/init.sql
```

### Verification

```bash
kubectl get pods -n beer-tracker
```

All pods should reach `Running` status.

### Accessing the application

The ingress controller is reachable at `$(minikube ip)` on port 80. On **Linux or WSL2**, that IP is only accessible within the VM/subsystem. Forward the ingress controller port to your local machine instead:

```bash
kubectl port-forward -n ingress-nginx \
  service/ingress-nginx-controller 8080:80
```

Leave this running, then open `http://localhost:8080` in your browser. All ingress routes are available through the single forwarded port:

| Path | Service |
|---|---|
| `/` | Frontend |
| `/auth/...` | Auth service |
| `/tracking/...` | Beer tracking |
| `/notifications/...` | Health notifications |
| `/statistics/...` | Statistics |

Stop the forward with `Ctrl-C`.

### Troubleshooting

| Symptom | Resolution |
|---|---|
| `ImagePullBackOff` | Images must be built inside the minikube Docker daemon. Run `eval $(minikube docker-env)` then rebuild. `values-minikube.yaml` sets `imagePullPolicy: Never`. |
| `Secret not found` | `deploy-minikube.sh` creates the secret. Re-run the script or manually create the secret with `kubectl create secret generic`. |
| Ingress returns 404 / not routing | Confirm `minikube addons enable ingress` completed. Check ingress class is `nginx` (set in `values-minikube.yaml`). |
| Pods stuck in `Pending` | Check node resources: `kubectl describe node minikube`. Increase minikube memory: `minikube start --memory=4096`. |

---

## Scenario 3 — Azure AKS

Production-grade deployment on Azure Kubernetes Service. Uses Azure Container Registry for images, Azure PostgreSQL Flexible Server for data, Azure Key Vault for secrets, and Azure Application Gateway as the ingress.

Infrastructure is defined in `infra/main.bicep` (and supporting modules: `acr.bicep`, `aks.bicep`, `keyvault.bicep`, `monitoring.bicep`, `network.bicep`, `postgres.bicep`). CI/CD runs via `.github/workflows/ci.yml`.

### Prerequisites

- **Azure CLI (`az`) ≥ 2.50** and an active subscription
- **Docker** (for building and pushing images to ACR)
- **kubectl**
- **helm ≥ 3.10**
- **jq**

### Setup

1. Create a service principal for deployment:

   ```bash
   az ad sp create-for-rbac --name beer-tracker-sp --sdk-auth
   ```

   Save the JSON output — you will need it for GitHub Actions secrets.

2. Set required environment variables:

   ```bash
   export AZURE_RESOURCE_GROUP=rg-beer-tracker
   export AZURE_LOCATION=eastus
   export POSTGRES_ADMIN_PASSWORD=<strong-password>
   export POSTGRES_APP_PASSWORD=<app-password>
   export INTERNAL_API_KEY=<random-secret>
   export AUTH_RSA_KEY_PATH=./secrets/auth-rs256-private-key.pem
   ```

   Ensure the RSA key exists at `AUTH_RSA_KEY_PATH` (see `secrets/README.md`).

3. Run the deployment script:

   ```bash
   ./scripts/deploy-azure.sh
   ```

   The script provisions infrastructure via Bicep, builds and pushes images to ACR, uploads the RSA key and other secrets to Key Vault, then deploys the Helm chart with `values-azure.yaml`.

4. One-time database schema initialisation — connect to the PostgreSQL Flexible Server and run the init script:

   ```bash
   psql "host=<flexible-server-fqdn> dbname=postgres user=psqladmin sslmode=require" \
     -f postgres-init/init.sql
   ```

   The FQDN is printed by `deploy-azure.sh` or retrievable via:

   ```bash
   az postgres flexible-server show \
     -g $AZURE_RESOURCE_GROUP -n beer-tracker-postgres \
     --query fullyQualifiedDomainName -o tsv
   ```

5. Grant the GitHub Actions service principal AKS RBAC access:

   ```bash
   AKS_ID=$(az aks show -g $AZURE_RESOURCE_GROUP -n $AKS_CLUSTER_NAME --query id -o tsv)
   az role assignment create --assignee <SP_OBJECT_ID> \
     --role "Azure Kubernetes Service RBAC Cluster Admin" --scope $AKS_ID
   ```

6. Set the following GitHub Actions repository secrets:

   | Secret | Value |
   |---|---|
   | `AZURE_CREDENTIALS` | JSON output from `az ad sp create-for-rbac` |
   | `ACR_LOGIN_SERVER` | e.g. `beertracker.azurecr.io` |
   | `AKS_CLUSTER_NAME` | Name of the AKS cluster |
   | `AZURE_RESOURCE_GROUP` | Resource group name |
   | `KEY_VAULT_NAME` | Name of the Azure Key Vault |
   | `AZURE_TENANT_ID` | Azure tenant ID |

### Verification

```bash
kubectl get pods -n beer-tracker
kubectl get ingress -n beer-tracker
```

Note the `ADDRESS` on the ingress — that is the Application Gateway public IP. All pods should reach `Running`. Allow 2–5 minutes for the Application Gateway to become healthy.

### Troubleshooting

| Symptom | Resolution |
|---|---|
| CSI driver volume mount fails | Confirm the pod's managed identity has `Key Vault Secrets User` role on the Key Vault. Check `kubectl describe pod` for the CSI error message. |
| `Forbidden` when accessing Key Vault | The Key Vault access policy or RBAC role assignment may be missing. Run `az keyvault show` to verify RBAC mode, then check role assignments. |
| Bicep deployment errors | Run `az deployment group show` to see the error detail. Common causes: quota limits, naming collisions, missing provider registrations. |
| Application Gateway returns 502 | Backend health probe failing. Check pod readiness (`kubectl get pods`) and ensure `initialDelaySeconds` is long enough for Spring Boot startup (~30 s). |
| ACR push denied | Re-login: `az acr login --name <acr-name>`. Confirm the SP has `AcrPush` role. |

---

## Troubleshooting

Cross-scenario issues that do not fit a single scenario.

### Port 8080 already in use (Compose)

```bash
lsof -i :8080
```

Kill or stop the conflicting process, or change the host port mapping in `docker-compose.yml`.

### RSA key not present

```bash
openssl genrsa -out secrets/auth-rs256-private-key.pem 2048
```

See `secrets/README.md` for full details on key management across scenarios.

### Services fail to start (health probe delays)

Spring Boot services take 20–40 seconds to start. In Kubernetes, increase `initialDelaySeconds` in the liveness/readiness probe if pods are being killed before they finish starting. In Compose, the `depends_on` conditions only wait for postgres; other services start as soon as postgres is healthy and will retry internally.

### Database connection failures

Verify that `POSTGRES_PASSWORD` in `.env` matches the value the postgres container was originally initialised with. If the volume already exists with a different password, remove it:

```bash
# Compose
podman compose down -v   # or docker compose down -v
podman compose up -d
```

In Kubernetes, delete the PVC and re-deploy to force re-initialisation.

### Logs

```bash
# Compose — tail all services
podman compose logs -f

# Compose — single service
podman compose logs -f auth-service

# Kubernetes
kubectl logs -n beer-tracker -l app=auth-service --tail=100 -f
```
