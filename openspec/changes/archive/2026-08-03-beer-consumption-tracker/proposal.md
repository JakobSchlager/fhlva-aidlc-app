## Why

There is no existing system to help individuals monitor and manage their beer consumption over time. This service provides a fun, socially-aware platform that logs drinks, surfaces personal statistics, and proactively warns users before they exceed safe consumption thresholds — combining transparency with health-conscious nudges.

## What Changes

- Introduce a web-based, microservice-structured application built from scratch
- Implement a **login/authentication service** providing secure user registration and JWT-based authentication
- Implement a **beer tracking service** allowing users to log beer consumption entries (type, quantity, timestamp)
- Implement a **health/notification service** that monitors consumption patterns and warns users when they approach or exceed recommended daily/weekly limits
- Implement a **statistics service** that aggregates and serves consumption data across users (averages, totals, trends)
- Provide a **TypeScript frontend** (single-page application) serving all user-facing interactions
- Back each service with a **PostgreSQL** database for persistent data storage
- Expose all service APIs via a shared API gateway / reverse proxy
- Introduce a **layered test strategy**: unit tests per Java service (already scoped), and Playwright browser-driven **end-to-end tests** covering the complete user journey from registration through statistics — ensuring API, proxy, and UI integrate correctly

## Capabilities

### New Capabilities

- `user-auth`: User registration, login, JWT issuance and validation, token refresh, and logout across all services
- `beer-tracking`: Recording beer consumption entries per user (beer type, volume, ABV, timestamp), retrieving history, updating and deleting entries
- `health-notifications`: Evaluating consumption against configurable daily/weekly limits, generating in-app warnings and notification events when thresholds are breached
- `statistics`: Aggregated consumption reports — personal totals, averages, trends over time, and anonymised cross-user comparisons
- `e2e-testing`: Browser-driven tests verifying integrated system behaviour end-to-end; complements per-service unit tests by catching failures at the API-proxy-UI boundary

### Modified Capabilities

<!-- No existing capabilities — greenfield project -->

## Impact

- **New repositories / modules**: Four backend Java services (`auth-service`, `beer-tracking-service`, `health-notification-service`, `statistics-service`), one TypeScript frontend (`frontend`), Helm charts per service, and an umbrella Helm chart for one-command AKS deployment
- **APIs introduced**: REST APIs for each service; inter-service communication via internal HTTP calls using Kubernetes ClusterIP Services (not exposed through ingress)
- **Infrastructure**: Azure Kubernetes Service (AKS) as the runtime platform; Azure Database for PostgreSQL Flexible Server (one database per service, VNet-integrated); Azure Container Registry (ACR) for storing container images; Azure Key Vault for secrets (JWT private key, DB passwords, internal API key); Application Gateway Ingress Controller (AGIC) or nginx Ingress Controller for external routing
- **Dependencies**: Spring Boot (Java services), React + Vite (TypeScript frontend), PostgreSQL JDBC driver, JWT library (e.g., jjwt), Axios/fetch (frontend HTTP client), Helm 3, Azure CLI / Bicep or Terraform for infrastructure provisioning
- **No breaking changes** — greenfield; no existing consumers
