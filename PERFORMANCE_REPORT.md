# Performance & Load Test Report

Brief summary of the test environment, issues resolved, adapted SLOs, and k6 benchmark results for Beer Tracker.

---

## 1. Environment & Setup

- **Host**: Linux / Podman 6.1.3
- **Environment**: Devcontainer with nested rootful Podman & containerd
- **Cluster**: Local Kubernetes (`minikube` v1.38.1, Kubernetes v1.35.1)
- **Application**: 5 microservices (`auth`, `tracking`, `statistics`, `notifications`, `frontend`) + Bitnami PostgreSQL
- **Test Driver**: `docker.io/grafana/k6:2.3.0` running as in-cluster Kubernetes Job

---

## 2. Issues Encountered & Resolutions

| Issue | Root Cause | Resolution |
|---|---|---|
| **Minikube Provisioning Failure** | Stale cluster state from previous machine profile. | Ran `minikube delete` and started with `devcontainer-minikube-start`. |
| **Helm Fetch Exit 255** | VS Code Remote Containers injected a host `credsStore` into `/root/.docker/config.json`. Helm OCI registry calls to Docker Hub failed on the broken credential helper. | Added automatic detection and fallback to a clean `DOCKER_CONFIG` in `scripts/deploy-minikube.sh`. |
| **Playwright Missing Libraries** | Container lacked headless Chromium system libraries. | Executed `devcontainer-install-playwright` from repository root. |
| **ConfigMap Apply Warning** | Duplicate `SPIKE_FACTOR` key in `load/k8s/run.env`. | Cleaned up duplicate keys in `run.env`. |

---

## 3. Adapted SLOs (`load/slo.json`)

Replaced the initial `1000ms` placeholder values with sensible production thresholds:

```json
{
  "errorRate": 0.01,
  "steps": {
    "statistics_me": { "p95": 150 },
    "statistics_trend": { "p95": 200 },
    "statistics_global": { "p95": 150 },
    "tracking_list": { "p95": 200 },
    "tracking_create": { "p95": 150 },
    "notifications_list": { "p95": 150 }
  }
}
```

- **Point reads/writes** (`statistics_me`, `statistics_global`, `tracking_create`, `notifications_list`): **`p95 < 150ms`**
- **Range & trend queries** (`statistics_trend`, `tracking_list`): **`p95 < 200ms`**
- **Error Budget**: `< 1.00%` failed requests (`0.00%` required for `smoke`)

---

## 4. Test Results Summary

All logs are stored in [`test-results/`](test-results/).

### 4.1 Profiles Overview

| Profile | Purpose / Shape | Requests | Complete Visits | Error Rate | Status | Log File |
|---|---|---|---|---|---|---|
| **Smoke** | Fast health check (1 VU, 30s) | 234 | 29 | **0.00%** | **PASS** | [`test-results/k6-smoke-adapted-slo.txt`](test-results/k6-smoke-adapted-slo.txt) |
| **Baseline** | Steady state (5 visits/s, 1m) | 1,665 | 300 | **0.00%** | **PASS** | [`test-results/k6-baseline-adapted-slo.txt`](test-results/k6-baseline-adapted-slo.txt) |
| **Gate** | Release gate (5 visits/s, 30s abort) | 875 | 151 | **0.00%** | **PASS** | [`test-results/k6-gate-adapted-slo.txt`](test-results/k6-gate-adapted-slo.txt) |
| **Spike** | Surge from 2 → 8 visits/s (3.5m) | 4,231 | 780 | **0.00%** | **PASS** | [`test-results/k6-spike-adapted-slo.txt`](test-results/k6-spike-adapted-slo.txt) |
| **Newcomers** | Heavy new user registration churn | 948 | 237 | **24.05%** | **BREACH** | [`test-results/k6-newcomers.txt`](test-results/k6-newcomers.txt) |
| **Playwright E2E**| Browser functional suite (19 tests) | 19 tests | — | **0.00%** | **PASS** (18 passed, 1 skipped) | [`test-results/playwright-e2e.txt`](test-results/playwright-e2e.txt) |

---

### 4.2 Latency vs Adapted SLOs (p95)

| Step (Endpoint) | Target SLO | Smoke Actual | Baseline Actual | Gate Actual | Spike Surge Actual |
|---|---|---|---|---|---|
| `statistics_me` | **< 150 ms** | 19.28 ms | 61.19 ms | 5.75 ms | **21.70 ms** |
| `statistics_trend` | **< 200 ms** | 17.70 ms | 58.02 ms | 38.07 ms | **36.94 ms** |
| `statistics_global` | **< 150 ms** | 47.71 ms | 86.57 ms | 13.95 ms | **23.27 ms** |
| `tracking_list` | **< 200 ms** | 55.29 ms | 74.64 ms | 5.36 ms | **22.23 ms** |
| `tracking_create` | **< 150 ms** | 72.21 ms | 67.57 ms | 12.94 ms | **20.95 ms** |
| `notifications_list`| **< 150 ms** | 46.36 ms | 89.22 ms | 10.85 ms | **23.28 ms** |
| `http_req_failed` | **0.00% / < 1%** | 0.00% | 0.00% | 0.00% | **0.00%** |

---

## 5. Key Findings

1. **High Resilience Under Traffic Surges**:
   During the **Spike profile**, traffic surged 4× (8 visits/sec, 16 concurrent VUs). The cluster served **4,231 requests with 0 errors** while keeping all p95 latencies under 40ms.
2. **Cold-User Onboarding Bottleneck (`newcomers`)**:
   While `auth_register` and `auth_login` maintained fast p95 latencies (~140–170ms), first-time stats calculation (`statistics_me_first`) timed out (>10s) when hundreds of new users concurrently registered and requested stats without warm caches.
