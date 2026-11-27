# Lab 4 setup trackers — Group 1

## Completed setup

- Variant A selected: the devcontainer reports 15 GiB total memory.
- `.env` and `secrets/auth-rs256-private-key.pem` were present inside `/workspaces/fhlva-aidlc-app`.
- A fresh Minikube cluster was created with `devcontainer-minikube-start --memory=6144`; its node reached `Ready`, and ingress was enabled.
- The five application images (`auth-service`, `beer-tracking-service`, `health-notification-service`, `statistics-service`, and `frontend`) built and loaded successfully.
- `./scripts/setup-gitops.sh --build-minikube-images latest` completed and printed `GitOps setup complete`.

## Issues found and fixes

- **Podman command location:** `podman` was not on the host shell's `PATH`, and Docker's default context did not list the devcontainer. Reached it using `/mnt/c/Users/jakob/AppData/Local/Programs/Podman/podman.exe`.
- **Windows Git CRLF caused an invalid k6 image reference.** The setup script read `docker.io/grafana/k6:2.3.0\r` from `charts/beer-tracker/values.yaml`, which Podman rejected. Set repo-local `core.autocrlf=input` and normalized that clean YAML file to LF. The setup script itself was left unchanged.
- **Helm could not fetch the Bitnami PostgreSQL OCI chart from Docker Hub.** Setup failed fetching `registry-1.docker.io/v2/bitnamicharts/postgresql/manifests/18.12.28`, despite the registry responding to curl. Fetched the chart layer directly using Docker Hub's anonymous token endpoint and installed chart `18.12.28` locally in both stage namespaces with the setup script's configured password and resource limits. Rerunning the setup script then completed successfully.

## Verified result

`kubectl get helmreleases -A` reported both HelmReleases `READY True`:

```text
NAMESPACE              NAME           READY   STATUS
beer-tracker-prod      beer-tracker   True    Helm install succeeded for release beer-tracker-prod/beer-tracker.v1
beer-tracker-staging   beer-tracker   True    Helm test succeeded for release beer-tracker-staging/beer-tracker.v1
```

Flux's GitRepository and all three Kustomizations also reported `READY True`. Application pods in both stages were Running, the staging k6 gate completed successfully, and the ingress controller is Running.

## Notes for tomorrow

Start Podman before reopening the devcontainer, then run `kubectl get helmreleases -A` to confirm the cluster survived restart. Do not run `minikube delete`. If Minikube reports a different boot ID after restart, follow the guide's troubleshooting table.

Non-blocking output observed: Minikube warned about running the Podman driver as root and reported an unavailable KIC artifact-download path, but it started and became Ready. The frontend build emitted a Vite chunk-size warning but completed.

## Lab 4 exercise — statistics-service canary

- Published both `ghcr.io/jakobschlager/statistics-service:latest` (stable) and `ghcr.io/jakobschlager/statistics-service:v2` (canary) to the public GHCR package. The latest image was published as well so changing the repository does not break the stable prod pod.
- Updated `deploy/stages/staging/helmrelease.yaml` to use the public GHCR `v2` image with `IfNotPresent`. Commit `5fa5685` was pushed to `JakobSchlager/fhlva-aidlc-app` `main`; anonymous access to the image manifest returned HTTP 200.
- Updated `deploy/stages/prod/helmrelease.yaml` on the same fork: statistics-service uses the GHCR repository, `IfNotPresent`, stable tag `latest`, and canary `enabled: true`, `tag: v2`, `replicas: 1`, `env: {}`. The prod k6 test remains disabled, matching Lab 4 step 7.
- Pushed prod canary commit `69266ac` to the fork's `main`. Flux for this cluster follows `https://github.com/JakobSchlager/fhlva-aidlc-app.git` at revision `main@sha1:69266ac1ee8abdaefa6617e131b2c2657dcf5369`.
- Loaded the two GHCR tags into Minikube and reconciled Flux. Production HelmRelease upgraded successfully and is `READY True`; staging remains `READY True` with its k6 Helm test succeeded.

Verified production canary pods and services:

```text
NAME                                                       READY   STATUS    TRACK    VERSION
beer-tracker-statistics-service-66df94b68d-rhcxk           1/1     Running   stable   latest
beer-tracker-statistics-service-canary-55ddc4fd5f-m2dgl    1/1     Running   canary   v2

beer-tracker-statistics-service          ClusterIP   10.109.156.53    8084/TCP
beer-tracker-statistics-service-canary   ClusterIP   10.111.214.210   8084/TCP
```

The regular Service selects stable and canary pods; the dedicated canary Service selects only the canary. The deployment is a 1:1 replica split, so production Service traffic is shared approximately evenly between the two versions.

## Lab 4 exercise — bad v3 canary / gate rollback

The bad-canary exercise was run from the fork at Flux revision `main@sha1:befe7e49a7d5629fb8bddcf56d6481bf7050da80`. Prod had the k6 test enabled and the canary configured as v3 with `BEER_TRACKING_INTERNAL_URL=http://beer-tracker-beer-tracking-service:9999`.

Observed evidence:

- The first v3 pod attempt could not pull `ghcr.io/jakobschlager/statistics-service:v3` (`ErrImagePull` / `ImagePullBackOff`, registry returned `not found`). A later retry pulled v3 successfully.
- The v3 canary did not become healthy; its startup probe got connection refused on port 8084. The k6 gate timed out calling `/statistics/me` through `beer-tracker-statistics-service-canary`.
- The gate failed: `http_req_failed` was **27.27% (6 of 22 requests)** against the `<1%` threshold, then k6 logged that it stopped after crossing the abort-on-fail threshold.
- Flux performed two failed upgrade/test attempts and rolled back both. The final HelmRelease condition is `Stalled=True / RetriesExceeded`, `Ready=False`; Helm revision 6 is deployed as a rollback to revision 4.
- Production served the previous good canary during rollback: stable `latest` and canary `v2` pods were both `1/1 Running`. The fork still requested v3 briefly while the HelmRelease was Stalled.
- The bad commit was reverted on the fork as `250bc81` (`Revert "canary statistics-service v3"`). Flux synced `main@sha1:250bc81ed7c71404ed29077bc6c68ce9f5b432df`; prod recovered to `Ready=True` at Helm revision 7, with stable `latest` and canary `v2` both `1/1 Running`. Staging remains Ready and its k6 Helm test succeeded.

This confirms the gate caught the deliberately broken v3 canary, rolled it back, and recovered after the revert was pushed.
