# Local Deployment & Testing Guide (Devcontainer)

A concise guide for running, accessing, and testing the application locally in the Devcontainer.

---

## 1. Start Cluster & Deploy Application

From the repository root inside the Devcontainer:

```bash
# Deploys application (starts minikube automatically if not running)
./scripts/deploy-minikube.sh

# Or deploy and immediately run the smoke test:
./scripts/deploy-minikube.sh --smoke-test
```

Verify all pods are running:
```bash
kubectl get pods -n beer-tracker
```

---

## 2. Web Browser Access

Forward the ingress port to make the application reachable on your machine:

```bash
kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80
```

- **Browser URL**: [http://localhost:8080](http://localhost:8080)
- **Port**: `8080`

### Available Endpoints:
- `/` — Frontend UI
- `/auth/...` — Auth Service
- `/tracking/...` — Beer Tracking Service
- `/statistics/...` — Statistics Service
- `/notifications/...` — Notifications Service

---

## 3. Smoke Test

Run a fast health check (1 VU, zero errors required):

```bash
./scripts/smoke-test.sh
```

---

## 4. Performance Tests (k6)

Run performance tests as in-cluster Kubernetes Jobs.

### Step 1: Set Profile in `load/k8s/run.env`
Edit `load/k8s/run.env` to configure your run:
- `PROFILE`: `smoke`, `baseline`, `spike`, `newcomers`, or `gate`
- `RATE`: target visits per second (default: `2`)
- `DURATION`: run duration (e.g. `2m`, `5m`)
- `SPIKE_FACTOR`: peak multiplier for `spike` (default: `5`)

### Step 2: Run Job
```bash
# 1. Update cluster ConfigMaps
kubectl apply -k load/ -n beer-tracker

# 2. Trigger test run
kubectl delete job k6-load -n beer-tracker 2>/dev/null || true
kubectl apply -f load/k8s/job.yaml -n beer-tracker

# 3. Stream results
kubectl logs -f job/k6-load -n beer-tracker
```

*(Optional)* Run directly against Compose stack instead of Kubernetes:
```bash
PROFILE=baseline RATE=5 DURATION=2m ./load/run-local.sh
```
