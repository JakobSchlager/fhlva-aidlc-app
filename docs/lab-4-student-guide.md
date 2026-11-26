# Lab 4 — Stages, gate and canary with Flux (group guide)

This guide sets up the delivery path for Lab 4 on your laptop and walks you through it once: a release to staging, a canary in prod, a bad canary that the gate stops, and the way back. The lab exercise that follows is in [`lab-4-slow-features.md`](lab-4-slow-features.md).

**Before the lab, at home: steps 1–4.** They download about 2 GB once. Check that `kubectl get helmreleases -A` shows `READY True` in every line, and report the result. Do not `minikube delete` afterwards. **In the lab: from step 5.**

**Where things run.** Every command block is marked:

- **[Host]**: on your laptop (Windows, macOS): Podman Desktop, VS Code, a browser, GitHub in the browser.
- **[Container]**: in a VS Code terminal *inside the devcontainer* (Terminal → New Terminal once the window says "Dev Container" bottom left).

Apart from opening the container and the browser, **everything runs in the container**. There is no script to run on Windows itself.

## Time

Steps 1–4 take about **20 min**, most of it waiting while step 4 runs on its own. If the cluster gets lost later, `minikube delete` and steps 3–4 again take about 5 min: the images stay cached in the devcontainer.

Flux checks GitHub once a minute, so every step after a push includes up to one minute of waiting. **Start step 4 as early as you can** — it runs on its own while you do something else.

## 1. Bring your fork up to date [Host]

Flux pulls from **your group's fork on GitHub**, not from your laptop.

1. On GitHub, open your fork and click **Sync fork** → **Update branch** so it contains the Lab 4 state of the course repository.
   If GitHub reports a conflict, your fork changed a file that the course also changed, most likely `load/script.js` in Lab 3. Your SLOs in `load/slo.json` are not affected (the course did not change that file). Resolve it in a pull request in your fork: take the course version of `script.js`, then re-apply your own change on top.
2. The fork must be **public**. Flux reads it without a token.

## 2. Open the devcontainer [Host] and pull [Container]

**[Host]** Start Podman Desktop (the Podman machine must be running), open the repository folder in VS Code, then **Dev Containers: Reopen in Container**. The container is the same as in Lab 3; no rebuild is needed.

**[Container]**

```bash
git checkout main
git pull
ls deploy/stages            # must list: prod  staging
free -g                     # look at "total" in the "Mem:" row
```

**Choose your variant from `free -g`:**

| `Mem: total` | Variant | What you get |
|---|---|---|
| 7 or more | **A**: minikube with 6 GiB, both stages | staging with automatic gate + prod with canary |
| less than 7 | **B**: minikube with 4 GiB, prod only | prod with canary and gate; no staging |

`free` shows the memory of the Podman machine, not of your laptop. On Windows the Podman machine runs in WSL, which by default gets half of the laptop's RAM: a 16 GB laptop should show about 7, an 8 GB laptop about 3. (Not yet checked on a student laptop.)

Why not both stages on 4 GiB: it runs, but under load the cluster runs short of memory and response times rise fifty-fold (p95 426 ms instead of 9 ms in the rehearsal). That looks like an incident and is not one.

## 3. A fresh minikube [Container]

The cluster from Lab 3 is replaced. Its memory size cannot be changed in place: `minikube start --memory=…` on an existing cluster silently keeps the old size.

```bash
minikube delete
```

Variant A:

```bash
devcontainer-minikube-start --memory=6144
```

Variant B:

```bash
devcontainer-minikube-start
```

Both:

```bash
minikube addons enable ingress
kubectl get nodes           # one node, Ready
```

## 4. Set up the stages and Flux [Container]

The script builds the five images into minikube, creates the stage namespaces with their own PostgreSQL, installs Flux and points it at your fork and current branch. It needs `.env` and the auth key from Lab 3:

```bash
ls .env secrets/auth-rs256-private-key.pem        # both there? then go on
```

If one is missing (a new laptop, a new clone):

```bash
cp .env.example .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/; s/^INTERNAL_API_KEY=.*/INTERNAL_API_KEY=$(openssl rand -hex 32)/" .env
openssl genrsa -out secrets/auth-rs256-private-key.pem 2048
```

Both stay on your laptop (they are in `.gitignore`).

Variant A:

```bash
./scripts/setup-gitops.sh --build-minikube-images latest
```

Variant B:

```bash
./scripts/setup-gitops.sh --build-minikube-images latest --stages prod
```

It ends with `GitOps setup complete. Flux now follows main at https://github.com/<your fork>`. If it stops with `branch … not found`, the branch is not pushed: `git push -u origin <branch>`.

---

> **▶ In the lab we continue here.** Steps 1–4 are the pre-work; if `kubectl get helmreleases -A` shows `READY True` in every line, you are ready.

## 5. Look around [Container], open the app [Host]

**[Container]**

```bash
kubectl get gitrepository,kustomizations -n flux-system   # which commit Flux has, what it applied
kubectl get helmreleases -A                               # one line per stage, READY True
kubectl get pods -n beer-tracker-prod -L track,app.kubernetes.io/version
helm history beer-tracker -n beer-tracker-prod            # every deployment of prod
```

Make the app reachable (leave this running in its own terminal):

```bash
kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80
```

**[Host]** Open <http://localhost:8080> in your browser. VS Code forwards port 8080 from the container (Ports tab). This is prod; staging has no ingress.

**From now on a stage changes only through Git:** edit `deploy/stages/<stage>/helmrelease.yaml`, commit, push. `kubectl edit` or `helm upgrade` on a stage is overwritten by Flux.

**Your SLOs.** The gate measures every release against `load/slo.json`. If your Lab 3 SLOs are not in there yet, put them in now (step names are the `name` tags in `load/script.js`), then commit and push. From then on every gate uses your numbers.

Two terminals are handy for the following steps: one for editing and pushing, one watching

```bash
kubectl get helmreleases -A -w
```

## 6. A release to staging (variant A only) [Container]

Build a new version of `statistics-service` (no code change needed; takes seconds). `build-images.sh` builds with the devcontainer's Podman, whose cache survives `minikube delete`, and loads the image into minikube:

```bash
./scripts/build-images.sh v2 statistics-service
```

In `deploy/stages/staging/helmrelease.yaml`, under `statistics-service:` set `image.tag: v2`. Then:

```bash
git commit -am "release statistics-service v2 to staging"
git push
```

Watch: Flux upgrades staging, then runs the k6 gate as a Helm test. Green when the HelmRelease says `Helm test succeeded`. If the gate fails, Flux rolls back by itself.

```bash
kubectl get events -n beer-tracker-staging --field-selector involvedObject.kind=HelmRelease
kubectl logs -n beer-tracker-staging beer-tracker-k6-gate       # the gate's result
helm history beer-tracker -n beer-tracker-staging
```

## 7. A canary in prod [Container]

Variant B: build the image first (step 6, first command only).

In `deploy/stages/prod/helmrelease.yaml`, in the `statistics-service` block:

```yaml
      canary:
        enabled: true
        tag: v2
        replicas: 1
        env: {}
```

Leave `replicaCount` out (default 1): one stable pod, one canary pod (more pods do not fit the laptop cluster). Commit and push.

```bash
kubectl get pods -n beer-tracker-prod -l app=statistics-service -L track,app.kubernetes.io/version
```

You should see one `stable`/`latest` pod and one `canary`/`v2` pod. The normal Service sends traffic to both, so about half of the prod requests to `statistics-service` now hit the new version. A second Service, `beer-tracker-statistics-service-canary`, reaches only the canary.

## 8. A bad canary, stopped by the gate [Container]

Prod has the gate off. Turn it on and ship a broken canary in the same commit. In `deploy/stages/prod/helmrelease.yaml`:

```yaml
  test:
    enable: true
  …
      canary:
        enabled: true
        tag: v3
        replicas: 1
        env:
          BEER_TRACKING_INTERNAL_URL: "http://beer-tracker-beer-tracking-service:9999"
```

```bash
./scripts/build-images.sh v3 statistics-service
git commit -am "canary statistics-service v3"
git push
```

What you should see within about three minutes:

- upgrade → gate fails → **rollback**, then one retry → gate fails → rollback again. Two failures per bad commit are the retry, not a second fault.
- The HelmRelease ends in `Stalled` (`RetriesExceeded`): Flux stops trying. Prod runs the previous revision.
- `kubectl logs -n beer-tracker-prod beer-tracker-k6-gate` shows `http_req_failed` above its threshold.

Note that the latency thresholds in the gate log can show green although the run aborted after a few requests.

## 9. Back to a good state [Container]

`Stalled` only clears with a new commit. Revert the bad one:

```bash
git revert --no-edit HEAD
git push
```

Prod is `Ready` again within about a minute and a half, with the v2 canary from step 7.

**Promote** the canary: set `image.tag: v2` for `statistics-service` and `canary.enabled: false`, in one commit. **Abort** instead: `canary.enabled: false`, or revert the commit that started the canary.

## 10. Next: break your own SLO

The lab exercise: every service has a slow feature behind a flag. Take your service's through this path and see whether your gate notices: [`lab-4-slow-features.md`](lab-4-slow-features.md).

## 11. Traffic on prod (optional) [Container]

The k6 settings for the stages come from Git (`load/k8s/run.env`, applied by Flux). A short run with these settings:

```bash
kubectl apply -f load/k8s/job.yaml -n beer-tracker-prod
kubectl logs -f job/k6-load -n beer-tracker-prod
kubectl delete job k6-load -n beer-tracker-prod      # before the next run
```

To change profile or rate, edit `load/k8s/run.env`, commit and push, as for any other stage change.

## If something goes wrong

| Symptom | Cause and fix |
|---|---|
| Nothing happens after a push | Flux polls once a minute. Check `kubectl get gitrepository -n flux-system`: does it show your latest commit? Did the push go to the branch Flux follows? |
| Pods in `ErrImageNeverPull` | The tag in `helmrelease.yaml` does not exist in minikube (for example after `minikube delete`). Build it again with `./scripts/build-images.sh <tag> <service>`. |
| HelmRelease `Stalled` | Expected after a failed gate. Push a fix or `git revert` the bad commit. |
| Pods restart, `OOMKilled`, PostgreSQL restarts | The cluster is short on memory. Check the variant (step 2). On variant B, do not raise `replicaCount`. |
| A chart change does not roll out | The stages only pick up a new chart `version` in `charts/beer-tracker/Chart.yaml`. Normally you only change `helmrelease.yaml`. |
| minikube does not start after a container restart ("boot ID differs") | `rm -rf /run/containers/networks /run/containers/storage /run/libpod`, `devcontainer-cgroup-init`, then `devcontainer-minikube-start` in a **new** terminal. If it then fails with `volume with name minikube already exists`: `minikube delete; sudo podman volume rm -f minikube` and start again (this loses the cluster: repeat step 4). |

More detail: the "GitOps stages (Flux)" section of the [README](../README.md#gitops-stages-flux).
