# Load driver (k6)

A [k6](https://grafana.com/docs/k6/latest/) load driver for Beer Tracker. One script replays the frontend's main journey against the public API; named profiles choose the load shape; `slo.json` turns your SLOs into pass/fail thresholds. It runs from the `grafana/k6` container image, so you do not need to install k6.

| File | Purpose |
|---|---|
| `script.js` | The journey, user setup, token handling, thresholds, Dynatrace tagging |
| `profiles.js` | Load profiles and their hard caps |
| `slo.json` | Your SLOs as thresholds — **placeholder values, replace them** |
| `run-local.sh` | Run against the Compose stack |
| `kustomization.yaml`, `k8s/run.env`, `k8s/job.yaml` | Run as a Kubernetes Job |
| `../charts/beer-tracker/templates/tests/k6-gate.yaml` | The `gate` profile as a Helm test |

## What one iteration does

`setup()` registers a pool of `USERS` test users (`load-<run-id>-<n>@example.com`), logs each in, logs one beer for each and opens their statistics once, so the measured load starts with warm caches. This traffic is tagged `phase=setup` and uses `setup_*` step names.

Then each iteration is one **visit**, as the frontend makes it:

| Step (`name` tag) | Request |
|---|---|
| `statistics_me` | `GET /statistics/me` |
| `statistics_trend` | `GET /statistics/me/trend?days=30` |
| `tracking_list` | `GET /tracking/entries?page=0&size=20` |
| `tracking_create` | `POST /tracking/entries` — only in a `WRITE_RATIO` share of visits |
| `statistics_global` | `GET /statistics/global` |
| `notifications_list` | `GET /notifications/warnings` |

Access tokens live 15 minutes (`jwtExpirationMs` in `auth-service`). Each VU renews its token at a random point in the last 20–30 % of its life (`auth_renew`), so long runs keep working and renewals do not arrive as one burst.

The `newcomers` profile is different: each iteration is a **new** user who registers, logs in, logs one beer and opens statistics for the first time (`statistics_me_first`).

## Profiles

Select with `PROFILE`. Defaults are low on purpose.

| Profile | Shape | Defaults | Caps |
|---|---|---|---|
| `smoke` | 1 VU, one visit per second | `DURATION=30s` | 2 min; any failed request fails the run |
| `baseline` | constant `RATE` visits/s | `RATE=2`, `DURATION=5m` | 4 h |
| `spike` | 1 min at `RATE` → 30 s ramp to `RATE × SPIKE_FACTOR` → hold `DURATION` → 30 s down → 1 min at `RATE` | `SPIKE_FACTOR=5`, `DURATION=5m` | hold 30 min |
| `newcomers` | ramp to `RATE × SPIKE_FACTOR` new users/s, hold `DURATION`, ramp down | `DURATION=3m` | hold 30 min |
| `gate` | constant `RATE` visits/s; thresholds abort the run as soon as they fail | `DURATION=1m` | 2 min |

All profiles are capped at 200 iterations/s and 300 VUs. `baseline`, `spike`, `newcomers` and `gate` use k6 **arrival-rate** executors (an open model): if the system slows down, k6 adds VUs to keep the rate instead of sending fewer requests. When it reaches the VU cap, k6 reports the iterations it could not start.

> **Not calibrated yet.** The default rates have not been measured against the lab environment. What saturates first, and at which rate, depends on node size, limits and data volume.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `PROFILE` | `smoke` | see above |
| `RATE` | `2` | iterations per second |
| `DURATION` | per profile | e.g. `90s`, `5m`, `1h30m` |
| `SPIKE_FACTOR` | `5` | peak = `RATE × SPIKE_FACTOR` |
| `USERS` | `20` | size of the user pool created in `setup()` (max 500) |
| `WRITE_RATIO` | `0.3` | share of visits that log a beer |
| `RUN_NAME` | `<profile>-<timestamp>` | load test name in the Dynatrace header |
| `SLO_FILE` | `./slo.json` | threshold file |
| `REQUEST_TIMEOUT` | `10s` | a slower request counts as failed |
| `BASE_URL` | `http://localhost:8080` | target for all services |
| `AUTH_URL`, `TRACKING_URL`, `STATISTICS_URL`, `NOTIFICATIONS_URL` | `BASE_URL` | per-service targets, e.g. in-cluster service names or a canary Service |

## SLOs as thresholds

Edit `slo.json`. `errorRate` is the allowed share of failed requests (0.01 = 1 %), across all steps. Under `steps`, give each step a `p95` and/or `p99` latency in milliseconds. A run that breaks a threshold ends with a non-zero exit code; the k6 summary marks the failing threshold. Exception: `smoke` always requires zero failed requests.

The same file is meant to become your release gate in Lab 4.

## Run against the Compose stack

Start the stack (`podman compose up -d` or `docker compose up -d`), then:

```bash
PROFILE=smoke ./load/run-local.sh
PROFILE=baseline RATE=5 DURATION=2m ./load/run-local.sh
PROFILE=gate ./load/run-local.sh
```

The script runs the k6 container on the Compose network and targets nginx directly (`http://nginx:80`). Extra arguments go to `k6 run`, e.g. `./load/run-local.sh --summary-export /dev/stdout`. Stop a run with `Ctrl+C`.

## Run in Kubernetes (minikube, AKS)

The Job reads the scripts and the run settings from two ConfigMaps. In namespace `beer-tracker` (adjust `-n` to yours):

```bash
# 1. Choose profile, rate and targets in load/k8s/run.env, then create/update the ConfigMaps
kubectl apply -k load/ -n beer-tracker

# 2. Start the run and follow it
kubectl apply -f load/k8s/job.yaml -n beer-tracker
kubectl logs -f job/k6-load -n beer-tracker

# 3. Stop it — also needed before the next run, because a Job cannot be changed once created
kubectl delete job k6-load -n beer-tracker
```

By default `run.env` targets the services directly by their in-cluster names, which keeps the ingress (and on AKS its IP allow-list) out of the way. To include the ingress hop, set `BASE_URL` to the ingress address and remove the four per-service URLs.

The Job stops after 4 hours at the latest (`activeDeadlineSeconds`), is never restarted (`backoffLimit: 0`), and is deleted an hour after it finishes.

## Gate as a Helm test

With `loadTest.enabled=true`, the umbrella chart contains a test pod that runs the `gate` profile against the release's services:

```bash
kubectl apply -k load/ -n beer-tracker
helm upgrade beer-tracker charts/beer-tracker -n beer-tracker --reuse-values --set loadTest.enabled=true
helm test beer-tracker -n beer-tracker --logs
```

`loadTest.env` overrides the pod's environment, e.g. `--set loadTest.env.STATISTICS_URL=http://<canary-service>:8084`.

## Dynatrace

Every request carries the header

```
x-dynatrace-test: VU=<vu>;SI=k6;LTN=<RUN_NAME>;LSN=beertracker-journey;TSN=<step>;
```

(`LSN=beertracker-newcomer` for the `newcomers` profile). To filter by it, define request attributes that extract these values from the header in Dynatrace. Without that, the header is harmless.

## What a run leaves behind

Every run creates users (`load-<run-id>-…@example.com`) and beer entries in the target database. There is no cleanup script yet; on a disposable environment, recreating the database volume is the simplest reset.

## Cost on AKS

Load raises CPU use and can make the node pool scale out (2–5 nodes). Keep `DURATION` bounded, delete finished Jobs, and do not leave a `baseline` running unattended.
