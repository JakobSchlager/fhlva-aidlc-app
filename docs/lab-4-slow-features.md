# Lab 4 — Break your own SLO: a slow feature behind a flag

Each service has a new feature that is **switched off by default**. Switched on, it works and nothing fails, but it is slower. Your group takes the feature of **your** service through the delivery path from the group guide ([`lab-4-student-guide.md`](lab-4-student-guide.md), steps 5–9) and finds out whether your SLOs and your gate notice.

Three ideas to take away:

- **Deploy ≠ release.** The new image with the flag off is the same product as before. Switching the flag on is a config-only commit, and that commit is the release that the gate has to judge.
- **The gate only knows what it is told.** It measures the steps in `load/script.js` against the numbers in `load/slo.json`. A slowdown on a path the script does not call, or within a loose SLO, passes.
- **A slow feature is a trade-off, not a bug.** Users may want it. Is it allowed to cost the latency? Change the SLO, make it faster, or ship it to a subset only?

## The features

All flags are environment variables, `true` to switch on. The code is in the file named; read it, the comment above the flag says what it does and why it costs time.

| Service | Flag | What the feature does | Why it is slower | Step it hits | Measured (gate, laptop) |
|---|---|---|---|---|---|
| `auth-service` | `FEATURE_STRONG_PASSWORD_HASH` | stronger password hashing (BCrypt cost 14 instead of 10) | each +1 doubles the CPU per hash: 16× per register and login | `setup_register`, `setup_login` (and `auth_renew`, but only in runs longer than ~11 min) | ~70 ms → **~1 s** |
| `beer-tracking-service` | `FEATURE_ENTRY_DAY_TOTALS` | the entry list shows standard drinks per entry and the day's total (the frontend's "Std. drinks" column fills in) | one extra database query per listed entry (N+1); grows with the user's history | `tracking_list` | 7 → 13 ms; with `SEED_ENTRIES=40`: **20–22 ms** |
| `statistics-service` | `FEATURE_LIVE_TREND` | the trend is always current, read live instead of from the cache | one HTTP call to `beer-tracking-service` per day (30 for the default 30 days), holding a database connection meanwhile | `statistics_trend` | 9 → **47 ms** |
| `health-notification-service` | `FEATURE_LIVE_WARNINGS` | warnings appear immediately instead of after the next scheduler run (5 min) | every list call first evaluates the user: 7 calls to `beer-tracking-service` plus database writes | `notifications_list` | 8 → **31 ms** |

Files: `auth-service/…/config/SecurityConfig.java`, `beer-tracking-service/…/service/EntryService.java`, `statistics-service/…/service/StatisticsService.java`, `health-notification-service/…/controller/WarningController.java`.

Measured on 2026-11-26 on minikube (Mac, 6 GiB), gate profile (1 min, 2 visits/s, 5 users). Your numbers will differ: **measure your own baseline first**.

## The exercise

Work through Git as in the group guide: edit `deploy/stages/<stage>/helmrelease.yaml` (and `load/`), commit, push, watch. Replace `statistics-service` and the flag below with your service and its flag.

### 1. Build the new version and release it with the flag off [Container]

```bash
git pull                                              # the feature code
./scripts/build-images.sh v4 statistics-service      # seconds: only your source changed
```

`build-images.sh` builds with the devcontainer's Podman (its cache survives `minikube delete`) and loads the image into minikube. In `deploy/stages/staging/helmrelease.yaml` set `image.tag: v4` for your service, commit, push. The gate passes: the flag is off, nothing changed for users.

**Variant B (prod only):** there is no staging. In step 1 release `v4` straight to prod (gate on, see step 3), and do step 2 there: with the flag in `canary.env`, the gate tests the canary.

### 2. Predict, then switch the flag on in staging

**Before you push**: write down what you expect. Which step gets slower, by how much, and does your gate catch it with your `slo.json`?

```yaml
    statistics-service:
      image:
        tag: v4
      env:
        FEATURE_LIVE_TREND: "true"
```

Commit, push, then read the gate's result per step:

```bash
kubectl logs -n beer-tracker-staging beer-tracker-k6-gate | grep -A1 'name:'
```

Was your prediction right? With the course's placeholder SLOs (`p95 < 1000 ms`) every feature passes. With your Lab 3 SLOs, maybe not.

### 3. Ship it to a subset: canary in prod with the flag on

Prod has the gate off; turn it on, and start the canary with the flag only in `canary.env`:

```yaml
  test:
    enable: true
  …
      canary:
        enabled: true
        tag: v4
        replicas: 1
        env:
          FEATURE_LIVE_TREND: "true"
```

While a canary runs, the gate tests that service **through the canary Service only**, so it sees the feature at full strength. Your users see it on about half of their requests:

```bash
kubectl apply -f load/k8s/job.yaml -n beer-tracker-prod        # 2 min of traffic on prod, both tracks
kubectl logs -f job/k6-load -n beer-tracker-prod
kubectl delete job k6-load -n beer-tracker-prod
```

Compare `p(50)` and `p(95)` of your step. In the rehearsal (statistics, flag on in the canary): p50 = 8 ms (the stable half), p95 = 39 ms. The median hides a slow canary; the tail shows it.

### 4. Make the gate catch it

If your gate stayed green, find out why, and fix it with a commit:

- **The SLO is too loose** → tighten your step in `load/slo.json` (for example `"statistics_trend": { "p95": 30 }`).
- **The script does not exercise the slow path** → add the step to `slo.json`, or a step to `load/script.js`. Auth: the visit loop never logs in; `setup_register` and `setup_login` are measured in setup, so `"setup_login": { "p95": 300 }` in `slo.json` counts. (`auth_renew` does not help in the gate: tokens live 15 min and are renewed after about 11, so a 1-minute gate never renews.)
- **The test data is too small** → beer-tracking: test users have one entry each. `SEED_ENTRIES` gives each user more history before the run; for the gate set it in the HelmRelease:

  ```yaml
    loadTest:
      enabled: true
      env:
        SEED_ENTRIES: "40"
  ```

**Watch out: an SLO change alone does not re-run the gate.** The gate runs on a release (a change to the HelmRelease). A commit that only touches `load/` updates the k6 ConfigMap, and the slow canary keeps running. To have the feature judged against the new SLO, release it again: one commit with the flag `"false"`, then one with `"true"`. Then: upgrade → gate fails → rollback → one retry → `Stalled`, prod back on the flag-off canary. In the rehearsal: `statistics_trend` p95 = 42 ms against 30 ms, the gate aborted after 10 s.

To check the running prod against your SLOs without a release: the k6 Job above uses the same `slo.json` and reports ✗ for a violated step (the Job ends `Failed`).

### 5. Decide

The feature works. Choose, and write down why:

- **Change the SLO**: the feature is worth the latency. Who agrees to that, and what does the error budget say?
- **Make it faster**: fix the code (one query or one call instead of N, a cache, fewer days), build `v5`, release it. Does the gate pass now?
- **Keep it on the canary**: a subset of users gets it while you decide.
- **Ship the code, not the feature**: promote the new image with the flag off (`image.tag: v4`, flag `"false"` or removed, `canary.enabled: false`). Users get everything else in v4; the feature waits until it is fast enough.

### 6. Stretch: break it harder, or build your own

- Turn the knob: `PASSWORD_HASH_STRENGTH` (auth, default 14; each +1 doubles), `SEED_ENTRIES` (beer-tracking, up to 200), `days=` in `script.js`'s `statistics_trend` request (statistics, up to 365), the number of days in `evaluateUserLive` (notifications).
- Stay under the 10-second request timeout (`REQUEST_TIMEOUT`); beyond it a slow request counts as an error, not as latency.
- Write your own slow feature behind a flag in your service, release it the same way, and see whether another group's gate would have caught it.

## Turning a feature off again

Set the flag to `"false"` (or remove it), or `canary.enabled: false`, commit, push. No new image needed: that is the point of a flag.
