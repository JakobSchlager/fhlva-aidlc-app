## Context

This is a greenfield web application targeting **Azure Kubernetes Service (AKS)** as the production runtime. There is no existing codebase to migrate or integrate with. The system must support multiple independently deployable services (microservices), each owning its own data, while presenting a unified experience via a single-page TypeScript frontend. The four core services are: `auth-service`, `beer-tracking-service`, `health-notification-service`, and `statistics-service`.

All backend services are written in Java (Spring Boot), containerised as Docker images, and deployed as Kubernetes Deployments. The frontend is a TypeScript SPA (React + Vite) served as a static build via an nginx container. Data persistence uses Azure Database for PostgreSQL Flexible Server with one database per service. Services communicate synchronously via REST over Kubernetes ClusterIP Services for request/response flows.

## Goals / Non-Goals

**Goals:**
- Establish a working, runnable multi-service architecture targeting AKS from the start
- Define clear API contracts between services and the frontend
- Implement JWT-based authentication shared across all services
- Store all consumption data durably in Azure Database for PostgreSQL Flexible Server
- Provide health-threshold warnings to the user when daily/weekly limits are breached
- Serve aggregated statistics without exposing PII cross-user
- Manage all secrets through Azure Key Vault with no long-lived credentials in container images or ConfigMaps
- Enable horizontal scaling of each service independently via Kubernetes HPA

**Non-Goals:**
- Real-time push notifications (WebSocket / SSE) — in-app polling is sufficient for v1
- Mobile native clients
- Social/friend features or public leaderboards
- OAuth2/OIDC external identity providers (username+password only for v1)
- Service mesh (Istio / Linkerd) — Kubernetes-native networking is sufficient for v1
- Multi-region deployment — single AKS cluster per environment for v1

## Decisions

### 1. Monorepo layout with per-service Maven projects and Helm charts

Each Java service is a self-contained Maven project under `/services/<name>/`. The TypeScript frontend lives at `/frontend/`. Each service also has a Helm chart at `/charts/<name>/`. A root umbrella Helm chart at `/charts/beer-tracker/` composes all services for one-command deployment to AKS.

A `docker-compose.yml` is retained at the repo root **for local development only** — it runs all services, a local PostgreSQL instance, and an nginx reverse proxy so developers can work without an AKS cluster. The Helm charts are the source of truth for production shape; docker-compose mirrors it at reduced fidelity.

**Alternatives considered:**
- Separate repos per service: increases autonomy but complicates coordinated Helm releases and local development.
- Kustomize instead of Helm: viable but Helm's templating is better suited for per-environment value overrides (dev / staging / prod).

### 2. JWT-based auth, verified per-service (unchanged)

`auth-service` issues signed JWTs (RS256) on login. Every other service validates the JWT signature using the auth-service's public key fetched at startup from `GET /auth/.well-known/jwks.json` (reachable cluster-internally via ClusterIP Service). No shared session store is needed.

The RS256 private key is stored in Azure Key Vault and mounted into the `auth-service` pod via the Secrets Store CSI Driver (see Decision 6). Other services only need the public key endpoint — no secret material is shared.

**Alternatives considered:**
- Opaque tokens with per-request introspection calls to auth-service: adds latency and a hard dependency on auth-service availability.
- API Gateway-level JWT validation (AGIC + Azure API Management): reduces service code but ties security logic to infra config and adds cost.

### 3. Azure Database for PostgreSQL Flexible Server — one database per service

Each service connects to its own database on an **Azure Database for PostgreSQL Flexible Server** instance. The Flexible Server is deployed into the same VNet as the AKS cluster using private endpoint / VNet injection, so no traffic traverses the public internet. Independent databases (not schemas on a shared connection) give each service its own connection pool limits and Flyway migration history.

Flyway migrations run automatically at service startup using the service's own credentials, stored in Key Vault.

**Alternatives considered:**
- Schema-per-service on a single Postgres instance: weaker isolation; connection pool contention; a single bad migration affects all services.
- Separate Flexible Server instances per service: maximum isolation but significantly higher cost for v1 — one instance with multiple databases is the pragmatic middle ground.
- Azure Cosmos DB for PostgreSQL (Citus): overkill for v1 scale; adds operational complexity.

### 4. Azure Container Registry (ACR) for all images

All service images are built in CI (GitHub Actions) and pushed to an **Azure Container Registry** instance. The AKS cluster is granted `acrpull` permission via a managed identity attachment (`az aks update --attach-acr`), so no registry credentials are stored in Kubernetes Secrets.

Image tags follow `<service-name>:<git-sha>` for traceability; Helm chart `values.yaml` files reference the image tag as a configurable value.

**Alternatives considered:**
- Docker Hub: no private registry controls; requires credential management.
- GitHub Container Registry: viable, but ACR is native to Azure and has tighter RBAC integration with AKS managed identity.

### 5. AKS Ingress: Application Gateway Ingress Controller (AGIC)

External HTTP(S) traffic is routed through an **Azure Application Gateway** managed by the AGIC add-on. AGIC translates Kubernetes `Ingress` resources into Application Gateway rules, providing TLS termination (Azure-managed certificate via Azure Key Vault integration), WAF policies, and path-based routing to each service's ClusterIP.

Internal service-to-service calls (e.g., `health-notification-service` → `beer-tracking-service` internal endpoint) use **ClusterIP Services** and are never exposed through the ingress. The internal `X-Internal-Key` header check remains the application-level guard; the ingress adds a network-level enforcement layer.

**Alternatives considered:**
- nginx Ingress Controller: lighter weight, easier to self-manage, and a viable swap if AGIC proves operationally heavy. The Helm chart's `ingress.class` value is parameterised so switching requires only a values change.
- Azure API Management (APIM) as the gateway: adds rich policy management but is disproportionate for v1.

### 6. Azure Key Vault + Secrets Store CSI Driver + Workload Identity

All secrets — RS256 private key (PEM), database passwords (one per service), and the internal API key — are stored in **Azure Key Vault**. Pods access Key Vault using **AKS Workload Identity**: each Kubernetes service account is federated with an Azure Managed Identity that has `Key Vault Secrets User` role on the vault.

The **Secrets Store CSI Driver** mounts secrets as files or environment variables into pods at startup. Pods do not start until all required secrets are successfully mounted — this surfaces misconfiguration early rather than at runtime.

No secrets appear in `application.yml`, ConfigMaps, or Helm `values.yaml`. Environment-specific Key Vault names are the only per-environment configuration needed.

**Alternatives considered:**
- Kubernetes Secrets from CI pipeline: secrets stored in etcd (encrypted at rest in AKS by default) but require rotation coordination between CI and cluster.
- Azure App Configuration: useful for feature flags and non-secret config; complementary to Key Vault, not a replacement for secret material.

### 7. Horizontal Pod Autoscaler (HPA) per service

Each service Deployment is paired with an **HPA** configured to scale between 1 and 5 replicas based on average CPU utilisation (target 60%). The `health-notification-service` scheduler is designed to be safe with multiple replicas: the `@Scheduled` evaluation job uses a database-level advisory lock so only one pod executes the evaluation at a time, preventing duplicate warnings.

**Alternatives considered:**
- KEDA (event-driven autoscaling): more flexible triggers (queue depth, custom metrics) but unnecessary for CPU-bound services at v1 scale.
- Fixed replica counts: simpler but wastes resources during off-peak hours and cannot absorb traffic spikes.

### 8. Observability: Azure Monitor + Container Insights

All Spring Boot services output **structured JSON logs** (via Logback with `logstash-logback-encoder`) to stdout. AKS + Container Insights forwards these to a **Log Analytics Workspace**. Kubernetes liveness and readiness probes are defined for every Deployment (`/actuator/health/liveness` and `/actuator/health/readiness` via Spring Boot Actuator).

Azure Monitor alerts are configured for: pod restart count > 3 in 5 minutes, and HTTP 5xx error rate > 1% sustained for 2 minutes (measured at the Application Gateway).

**Alternatives considered:**
- Prometheus + Grafana on-cluster: more control and richer dashboards but adds operational burden. Spring Boot Actuator metrics can be scraped by Azure Managed Prometheus (AKS add-on) as a future upgrade path.

### 10. Playwright end-to-end test suite

End-to-end tests live in a dedicated `e2e/` directory at the repo root and use `@playwright/test`. The test target is the full docker-compose stack at `http://localhost:8080`. Tests are organised by user journey: `auth.spec.ts`, `dashboard.spec.ts`, `history.spec.ts`, `notifications.spec.ts`, `statistics.spec.ts`.

A `loggedInPage` fixture registers a unique test user (`test-<uuid>@example.com`) via the API and logs in through the UI, storing the resulting auth session. Individual tests consume this fixture rather than repeating the login flow, keeping test runtime short and failures isolated to the feature under test.

The suite is added to the GitHub Actions CI workflow as a `playwright-e2e` job that runs after `deploy` succeeds on the main branch: the job starts docker-compose, waits for services to be healthy, executes `npx playwright test`, and uploads the HTML report as an artifact.

**Alternatives considered:**
- Cypress: heavier install, slower startup; Playwright's multi-browser support and first-class TypeScript are better fits here.
- Testing Library (component-level): already implied for React unit tests; Playwright covers the nginx proxy routing and API integration that component tests cannot reach.

### 9. Frontend: React + Vite + TypeScript (served via nginx container)

Standard SPA with React Router for client-side routing. Axios for HTTP. No state management library for v1 (React context + hooks is sufficient). Tailwind CSS for styling. The production build (`vite build`) is served by an nginx container image. The nginx container is deployed as a Kubernetes Deployment behind the AGIC ingress at path `/`.

**Alternatives considered:**
- Azure Static Web Apps: managed hosting with built-in CDN and auth, but limits flexibility on custom auth flow (JWT cookie handling).
- Next.js: SSR adds complexity not needed for a data-entry/dashboard app.

## Risks / Trade-offs

- **Key Vault CSI startup dependency**: If Key Vault is unreachable at pod startup, the pod fails to start. → Mitigation: ensure VNet peering and private endpoint DNS are validated before deploying workloads; add readiness gate in Helm chart.
- **Flexible Server cold-start latency**: First connection after an idle period may be slow if connection pooling is not configured. → Mitigation: configure PgBouncer sidecar or use Spring Boot's HikariCP minimum-idle pool setting.
- **AGIC WAF false positives**: WAF rules may block legitimate requests (e.g., beer names containing special characters in POST bodies). → Mitigation: start with WAF in Detection mode, promote to Prevention after baseline tuning.
- **Scheduler duplicate execution under HPA**: Multiple `health-notification-service` replicas would each attempt the 5-minute evaluation. → Mitigation: database advisory lock (see Decision 7); alternatively, use a single-replica Deployment for this service if locking adds complexity.
- **Polling for notifications adds latency**: User may not see warnings for up to 5 minutes after crossing a threshold. → Acceptable for v1; upgrade to SSE/WebSocket in a future iteration.
- **Statistics staleness**: Cached aggregates may lag real consumption by the 15-minute refresh interval. → Surface `cachedAt` timestamp in the UI.
- **No email/SMS notifications in v1**: Warnings are in-app only, easy to miss. → Acceptable scope boundary; Azure Communication Services integration is a natural follow-up.

## Migration Plan

This is a greenfield deployment; no migration of existing data is required.

**One-time Azure infrastructure provisioning (Bicep or Terraform, run once per environment):**
1. Create Resource Group, VNet, and subnets (AKS node subnet, App Gateway subnet, PostgreSQL delegated subnet)
2. Provision Azure Container Registry; assign `acrpull` to AKS managed identity
3. Provision AKS cluster with AGIC add-on, Workload Identity add-on, Secrets Store CSI Driver add-on, and Container Insights enabled
4. Provision Azure Database for PostgreSQL Flexible Server; create one database per service; store credentials in Key Vault
5. Provision Azure Key Vault; store RS256 private key, DB passwords, internal API key; create federated credentials for each service's Kubernetes service account
6. Provision Log Analytics Workspace; link to AKS cluster for Container Insights

**Per-deployment sequence (CI/CD pipeline or manual):**
1. Build Docker images; push to ACR with `<git-sha>` tag
2. `helm upgrade --install beer-tracker ./charts/beer-tracker --set image.tag=<git-sha>` (umbrella chart)
3. Kubernetes applies Deployments; Secrets Store CSI mounts Key Vault secrets; Flyway migrations run on first pod startup
4. Services reach Ready state once liveness/readiness probes pass

**Rollback**: `helm rollback beer-tracker <revision>` redeploys the previous image tags. Database schema is forward-only (Flyway); a schema rollback script must be prepared manually if a migration needs reverting.

**Local development**: `docker-compose up` starts all services with a local PostgreSQL instance and nginx — no Azure account required for day-to-day development.

## Open Questions

- Should AGIC or nginx Ingress Controller be used? (AGIC is recommended; nginx is the fallback if WAF tuning proves costly in v1.)
- What are the configurable daily/weekly consumption thresholds? (Default: 2 standard drinks/day, 14/week — WHO low-risk guidelines.)
- Should the statistics service expose anonymised cross-user data in v1, or only personal stats?
- Are there internationalisation (i18n) requirements for the frontend?
- Should a single Flexible Server instance host all four databases, or should `auth-service` use a separate instance for stronger isolation?
- Is Azure Managed Prometheus (AKS add-on) preferred over Container Insights for metrics, or should both be enabled?
