## 0. Azure Infrastructure Provisioning

- [x] 0.1 Create Resource Group, VNet, and subnets (AKS node subnet, Application Gateway subnet, PostgreSQL delegated subnet) using Bicep or Terraform
- [x] 0.2 Provision Azure Container Registry (ACR); note the registry login server name for use in Helm values
- [x] 0.3 Provision AKS cluster with the following add-ons enabled: AGIC (Application Gateway Ingress Controller), Workload Identity, Secrets Store CSI Driver, Container Insights; attach ACR to grant the cluster `acrpull` permission
- [x] 0.4 Provision Azure Database for PostgreSQL Flexible Server in the PostgreSQL delegated subnet; create four databases: `auth_db`, `tracking_db`, `notifications_db`, `statistics_db`
- [x] 0.5 Provision Azure Key Vault; store the following secrets: `auth-rs256-private-key` (PEM), `auth-db-password`, `tracking-db-password`, `notifications-db-password`, `statistics-db-password`, `internal-api-key`
- [x] 0.6 Create one Azure Managed Identity per service; assign each the `Key Vault Secrets User` role on the Key Vault; create a federated credential linking each Managed Identity to its corresponding Kubernetes service account (namespace: `beer-tracker`)
- [x] 0.7 Provision a Log Analytics Workspace; link it to the AKS cluster for Container Insights log forwarding
- [x] 0.8 Configure Azure Monitor alert rules: pod restart count > 3 in 5 minutes; HTTP 5xx error rate > 1% sustained for 2 minutes (measured at Application Gateway)

## 1. Project Scaffolding

- [x] 1.1 Create monorepo directory structure: `/services/auth-service`, `/services/beer-tracking-service`, `/services/health-notification-service`, `/services/statistics-service`, `/frontend`, `/charts`
- [x] 1.2 Add root `docker-compose.yml` for **local development only** — services for PostgreSQL, nginx reverse proxy, and all four Java services and the frontend (mirrors AKS topology at reduced fidelity)
- [x] 1.3 Add local nginx reverse proxy config routing `/auth/**` → auth-service:8081, `/tracking/**` → beer-tracking-service:8082, `/notifications/**` → health-notification-service:8083, `/statistics/**` → statistics-service:8084, and `/` → frontend:3000 (local dev only)
- [x] 1.4 Create per-service `application.yml` with datasource, server port, JWT public key endpoint config, and Spring Boot Actuator health endpoints (`/actuator/health/liveness`, `/actuator/health/readiness`)
- [x] 1.5 Add `logstash-logback-encoder` dependency to each Java service and configure `logback-spring.xml` for structured JSON output to stdout
- [x] 1.6 Create Helm chart skeleton for each service under `/charts/<service-name>/` with: `Chart.yaml`, `values.yaml`, `templates/deployment.yaml`, `templates/service.yaml`, `templates/hpa.yaml`, `templates/configmap.yaml`, `templates/serviceaccount.yaml`, `templates/secretproviderclass.yaml`
- [x] 1.7 Create umbrella Helm chart at `/charts/beer-tracker/` that declares all four service charts and the frontend as dependencies; add a shared `values.yaml` with `image.registry`, `image.tag`, `keyVault.name`, and `ingress.class` as top-level configurable values
- [x] 1.8 Add `templates/ingress.yaml` to the umbrella chart with AGIC annotations; configure path-based routing: `/auth` → auth-service, `/tracking` → beer-tracking-service, `/notifications` → health-notification-service, `/statistics` → statistics-service, `/` → frontend
- [x] 1.9 Add HPA configuration to each service chart: min 1 replica, max 5 replicas, target CPU utilisation 60%
- [x] 1.10 Add a GitHub Actions CI workflow: build Docker images for all services, push to ACR with `<git-sha>` tag, run `helm upgrade --install` against the AKS cluster

## 2. Auth Service (`auth-service`)

- [x] 2.1 Initialise Spring Boot Maven project with dependencies: Spring Web, Spring Data JPA, Spring Security, PostgreSQL JDBC, Flyway, jjwt, Spring Boot Actuator, logstash-logback-encoder
- [x] 2.2 Create Flyway migration `V1__create_users_table.sql` with columns: `id`, `email` (unique), `password_hash`, `created_at`
- [x] 2.3 Create Flyway migration `V2__create_refresh_tokens_table.sql` with columns: `id`, `user_id`, `token_hash`, `expires_at`, `revoked`
- [x] 2.4 Configure service to read RS256 private key from the file path mounted by the Secrets Store CSI Driver (env var `AUTH_PRIVATE_KEY_PATH`); expose public key at `GET /auth/.well-known/jwks.json`
- [x] 2.5 Implement `POST /auth/register` — validate input, hash password with bcrypt, persist user, return 201 with `id` and `email`
- [x] 2.6 Implement `POST /auth/login` — verify credentials, issue 15-min JWT, issue 7-day refresh token in `HttpOnly` cookie, return 200 with `accessToken`
- [x] 2.7 Implement `POST /auth/refresh` — validate and rotate refresh token, return new `accessToken` and new cookie
- [x] 2.8 Implement `POST /auth/logout` — revoke refresh token, clear cookie, return 204
- [x] 2.9 Configure `SecretProviderClass` in the auth-service Helm chart to mount `auth-rs256-private-key` and `auth-db-password` from Key Vault into the pod
- [x] 2.10 Write unit tests for registration (duplicate email, weak password), login (valid, invalid), and token rotation

## 3. Beer Tracking Service (`beer-tracking-service`)

- [x] 3.1 Initialise Spring Boot Maven project with dependencies: Spring Web, Spring Data JPA, Spring Security, PostgreSQL JDBC, Flyway, Spring Boot Actuator, logstash-logback-encoder
- [x] 3.2 Fetch JWKS from auth-service ClusterIP Service at startup (`http://auth-service/auth/.well-known/jwks.json`) and configure JWT filter to validate RS256 Bearer tokens
- [x] 3.3 Create Flyway migration `V1__create_entries_table.sql` with columns: `id`, `user_id`, `beer_name`, `volume_ml`, `abv`, `timestamp`, `created_at`
- [x] 3.4 Implement `POST /tracking/entries` — validate fields (volume > 0, ABV 0–100), associate with JWT user, persist, return 201
- [x] 3.5 Implement `GET /tracking/entries` — paginated, newest first, with optional `from`/`to` query filters
- [x] 3.6 Implement `PUT /tracking/entries/{id}` — ownership check (403 if mismatch), full update, return 200
- [x] 3.7 Implement `DELETE /tracking/entries/{id}` — ownership check, delete, return 204
- [x] 3.8 Implement internal `GET /internal/tracking/summary` — validate `X-Internal-Key` header (value read from Key Vault-mounted secret), compute `totalVolumeMl` and `totalStandardDrinks` for given `userId` + date window; the internal ClusterIP Service for this endpoint is NOT listed in the Ingress resource
- [x] 3.9 Configure `SecretProviderClass` in the beer-tracking Helm chart to mount `tracking-db-password` and `internal-api-key` from Key Vault
- [x] 3.10 Write integration tests for CRUD operations and the internal summary endpoint

## 4. Health Notification Service (`health-notification-service`)

- [x] 4.1 Initialise Spring Boot Maven project with dependencies: Spring Web, Spring Data JPA, Spring Security, Spring Scheduler, PostgreSQL JDBC, Flyway, Spring Boot Actuator, logstash-logback-encoder
- [x] 4.2 Configure JWKS validation pointing to auth-service ClusterIP Service (same pattern as tracking service)
- [x] 4.3 Create Flyway migration `V1__create_warnings_table.sql` with columns: `id`, `user_id`, `type` (DAILY_EXCEEDED / WEEKLY_EXCEEDED), `status` (ACTIVE / RESOLVED / ACKNOWLEDGED), `triggered_at`, `resolved_at`, `acknowledged_at`, `threshold`
- [x] 4.4 Add a `scheduler_lock` table (Flyway `V2`) and implement a PostgreSQL advisory lock around the `@Scheduled` evaluation job so only one pod executes it when the HPA scales to multiple replicas
- [x] 4.5 Implement scheduled evaluation job (every 5 minutes) — call beer-tracking-service internal API (`http://beer-tracking-service/internal/tracking/summary`) with `X-Internal-Key` header, compare against configurable thresholds, create/resolve warnings
- [x] 4.6 Read thresholds from env vars `THRESHOLD_DAILY_DRINKS` and `THRESHOLD_WEEKLY_DRINKS` (sourced from ConfigMap) with defaults 2 and 14
- [x] 4.7 Implement `GET /notifications/warnings` — return paginated warnings for authenticated user with optional `status` filter
- [x] 4.8 Implement `POST /notifications/warnings/{id}/acknowledge` — ownership check, set ACKNOWLEDGED, return 200
- [x] 4.9 Configure `SecretProviderClass` in the health-notification Helm chart to mount `notifications-db-password` and `internal-api-key` from Key Vault
- [x] 4.10 Write unit tests for threshold evaluation logic (below, at, above daily and weekly limits) and advisory lock behaviour

## 5. Statistics Service (`statistics-service`)

- [x] 5.1 Initialise Spring Boot Maven project with dependencies: Spring Web, Spring Data JPA, Spring Security, Spring Scheduler, PostgreSQL JDBC, Flyway, Spring Boot Actuator, logstash-logback-encoder
- [x] 5.2 Configure JWKS validation pointing to auth-service ClusterIP Service
- [x] 5.3 Create Flyway migration `V1__create_stat_cache_tables.sql` for personal stats cache and global stats cache with `cached_at` columns
- [x] 5.4 Implement scheduled cache refresh (every 15 minutes) — call beer-tracking-service internal API, aggregate by user, store in cache tables
- [x] 5.5 Implement `GET /statistics/me` — return personal stats from cache for authenticated user (with optional `from`/`to` filters triggering on-demand computation)
- [x] 5.6 Implement `GET /statistics/me/trend` — return daily standard drinks array for last N days (default 30, max 365); validate max and return 400 if exceeded
- [x] 5.7 Implement `GET /statistics/global` — return anonymised aggregates (`activeUsers`, `globalAvgDrinksPerDay`, `topBeerNames`) from cache; no PII
- [x] 5.8 Include `cachedAt` in all response bodies; serve stale cache data with 200 if last refresh failed
- [x] 5.9 Configure `SecretProviderClass` in the statistics Helm chart to mount `statistics-db-password` and `internal-api-key` from Key Vault
- [x] 5.10 Write unit tests for trend computation (zero-fill missing days) and global stats anonymisation

## 6. Frontend (`frontend`)

- [x] 6.1 Scaffold React + Vite + TypeScript project; add React Router, Axios, Tailwind CSS
- [x] 6.2 Implement auth store (React context): store `accessToken` in memory, trigger refresh via `/auth/refresh` before expiry
- [x] 6.3 Build registration page — form with email and password fields, POST to `/auth/register`, redirect to login on success
- [x] 6.4 Build login page — form with email and password, POST to `/auth/login`, store token, redirect to dashboard
- [x] 6.5 Build beer entry form — fields: beer name, volume (ml), ABV (%), optional timestamp; POST to `/tracking/entries`
- [x] 6.6 Build consumption history table — paginated list with date-range filter controls; GET `/tracking/entries`
- [x] 6.7 Build personal statistics page — display total entries, total volume, avg drinks/day, day-of-week breakdown bar chart
- [x] 6.8 Build trend chart — line chart of daily standard drinks over last 30 days using `/statistics/me/trend`
- [x] 6.9 Build notifications panel — poll `/notifications/warnings?status=ACTIVE` every 60 seconds; display banner for each active warning with an "Acknowledge" button
- [x] 6.10 Build global statistics page — display `activeUsers`, `globalAvgDrinksPerDay`, `topBeerNames` from `/statistics/global`
- [x] 6.11 Add Axios interceptor to attach Bearer token to all requests and handle 401 by redirecting to login
- [x] 6.12 Write a multi-stage `Dockerfile`: stage 1 runs `vite build`, stage 2 copies the dist into an nginx base image; push to ACR as `frontend:<git-sha>`

## 7. Integration and Verification

<!-- These tasks require a live Azure environment and cannot be automated as code. -->
<!-- Run these manually after deploying with: helm upgrade --install beer-tracker ./charts/beer-tracker ... -->

- [x] 7.1 Verify local development: run `docker-compose up`, confirm all services start and Flyway migrations complete without errors
- [ ] 7.2 Build all Docker images and push to ACR: confirm each image appears in ACR with the correct `<git-sha>` tag
- [ ] 7.3 Run `helm upgrade --install beer-tracker ./charts/beer-tracker --namespace beer-tracker --create-namespace --set image.tag=<git-sha>`; confirm all pods reach `Running` state with liveness and readiness probes green
- [ ] 7.4 Verify Secrets Store CSI mounts: exec into each pod and confirm the expected secret files are present at the mounted path; confirm no secrets appear in pod environment variable dumps that were not sourced from Key Vault
- [ ] 7.5 Verify AGIC routing: confirm external requests to `/auth`, `/tracking`, `/notifications`, `/statistics` reach the correct service pods; confirm `/internal/tracking/summary` is NOT reachable through the ingress (expect 404 or connection refused from outside the cluster)
- [ ] 7.6 Manually register a user, log in, log beer entries, and verify history appears correctly end-to-end through the AKS ingress
- [ ] 7.7 Verify health-notification service creates an ACTIVE warning after simulating overconsumption; verify the advisory lock prevents duplicate warnings when two pods are running simultaneously
- [ ] 7.8 Verify statistics service cache refresh populates personal and global stats; check `cachedAt` timestamp is present in responses
- [ ] 7.9 Verify HPA is configured: run `kubectl get hpa -n beer-tracker` and confirm all four HPAs show current/desired replicas; apply a load test to one service and confirm it scales up
- [ ] 7.10 Verify observability: confirm structured JSON logs appear in the Log Analytics Workspace; confirm Container Insights shows pod CPU/memory metrics; trigger a test alert and verify it fires in Azure Monitor

## 8. Playwright E2E Tests

- [x] 8.1 Create `e2e/` directory at repo root; initialise with `npm init @playwright/test`; configure `playwright.config.ts` (baseURL: `http://localhost:8080`, reporter: html, retries: 1, project: chromium headless)
- [x] 8.2 Add `loggedInPage` fixture: register a unique test user (`test-<uuid>@example.com`) via API, log in through the UI, expose the authenticated `Page` object to tests; add `globalSetup` to verify the stack is reachable before tests run
- [x] 8.3 Write auth tests (`e2e/tests/auth.spec.ts`): register with valid credentials → redirected to dashboard; register with duplicate email → error shown; register with short password → validation error shown; login with valid credentials → dashboard visible; login with wrong password → error shown
- [x] 8.4 Write dashboard tests (`e2e/tests/dashboard.spec.ts`): dashboard page renders stat tiles (not empty); beer entry form is visible and submittable; after submitting an entry the history table shows the new row
- [x] 8.5 Write history tests (`e2e/tests/history.spec.ts`): history page loads and shows entries; date-range filter narrows results; edit an entry and confirm updated values appear; delete an entry and confirm it is removed
- [x] 8.6 Write notifications tests (`e2e/tests/notifications.spec.ts`): notifications panel renders on dashboard; after logging entries with high ABV the panel shows an ACTIVE warning banner within the polling interval; clicking Acknowledge removes the banner
- [x] 8.7 Write statistics tests (`e2e/tests/statistics.spec.ts`): `/stats` page renders bar chart and trend line chart without errors; `/global` page renders `activeUsers`, `globalAvgDrinksPerDay`, and `topBeerNames`; `cachedAt` timestamp is displayed on both pages
- [x] 8.8 Add E2E npm scripts to `e2e/package.json`: `test:e2e` (headless), `test:e2e:ui` (Playwright UI mode); document in README that `podman compose up` must be running before executing tests
- [x] 8.9 Add a `playwright-e2e` job to `.github/workflows/ci.yml` triggered after the `deploy` job on main: start docker-compose, wait for services healthy, run `npx playwright test`, upload HTML report as a CI artifact
