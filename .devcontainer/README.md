# Development container (Podman)

A container with everything needed to develop, test and deploy Beer Tracker: JDK, Maven, Node, the compose
stack, minikube, Terraform and the Azure CLI. It runs on **Podman**, the team's container engine, and
needs no tooling on your machine except Podman and VS Code.

Design and evidence: [`openspec/changes/archive/2026-10-07-add-podman-devcontainer/`](../openspec/changes/archive/2026-10-07-add-podman-devcontainer/)
(`design.md` has every measurement and the reasoning behind each choice).

## What has been tested

| Host | Status |
|---|---|
| **Windows 11** with Podman Desktop (WSL machine, rootful), VS Code | **Tested** through the VS Code UI, 2026-10-07: opening the container, compose stack, end-to-end tests, minikube deployment, `az login`. Single runs. Terraform validation and the other Azure steps were reported done without captured output. |
| Linux under WSL2, rootful Podman | Tested with a throwaway image and scripts, **not** through VS Code. |
| **Native Linux** | **Not tested.** See [Linux](#linux-not-tested). |
| **macOS** on Apple Silicon (arm64), Podman 6.1.3, applehv machine, rootful | **Partly tested**, 2026-10-09, single runs: image builds natively for arm64, container starts, compose stack, `devcontainer-install-playwright`, e2e suite against compose (1 failure), minikube deployment (`devcontainer-minikube-start` 1 min 42 s including downloads, `deploy-minikube.sh` 8 min), e2e suite against minikube through the port-forward (16 passed, 1 skipped, 2 failed). All three failures were races in the tests, not platform-specific: "submitting a beer entry causes it to appear in history" navigated away before its POST completed, and "delete entry removes the row" counted the rows before they had loaded. Both are fixed; afterwards `dashboard.spec.ts` and `history.spec.ts` passed 5 of 5 repeats against minikube. **Not yet run:** Azure, the VS Code UI. See [macOS](#macos-partly-tested). |

Tested combination: VS Code 1.140.0, Dev Containers extension 0.469.0, Podman 6.0.2 on the host (Windows 11
Enterprise 10.0.26200). Other versions may work; nobody has checked. The VS Code documentation says Podman 5 or
newer, while the main README says Podman 4 or newer; only 6.0.2 was tried with VS Code.

## What you get

| Tool | Version in the image |
|---|---|
| JDK (Eclipse Temurin) | 21.0.12.1 |
| Maven | 3.9.16 |
| Node.js / npm | v20.20.2 / 10.8.2 |
| Terraform | 1.16.1 |
| Azure CLI | 2.91.0 |
| kubectl / Helm / minikube | v1.34.1 / v4.3.0 / v1.38.1 |
| Podman (inside the container) | 5.8.7, with `podman-docker` so `docker` runs Podman |
| Compose provider | `podman-compose` 1.6.0 (the only one installed) |
| PostgreSQL client, git, openssl | distro versions of the Fedora base image |

Helper commands, installed in the image:

| Command | What it does | Runs automatically? |
|---|---|---|
| `devcontainer-cgroup-init` | lets nested containers and minikube create cgroups | yes, on every start |
| `devcontainer-healthcheck-runner start\|stop\|status` | runs Podman health checks (there is no systemd); log: `/var/log/devcontainer-healthcheck-runner.log` | yes, on every start |
| `devcontainer-minikube-start [args]` | starts minikube with the options this container needs | no |
| `devcontainer-install-playwright` | installs Chromium, its libraries and fonts for the e2e tests | no, opt-in |

Forwarded ports: 8080 (nginx), 8081 to 8084 (the four services), 5173 (Vite).

## Host prerequisites

### All hosts

1. **Podman**, and **VS Code** with the **Dev Containers** extension.
2. **The Podman engine that starts the container must be rootful.** Check before opening the container:
   ```
   podman info --format "{{.Host.Security.Rootless}}"
   ```
   It must print `false`. The container runs Podman inside itself, and on a rootless host nested minikube
   did not work (the kubelet could not write kernel settings, and pod networking failed).
3. **Two VS Code user settings** (Settings, JSON). They are application-scope settings, so `devcontainer.json`
   cannot carry them:
   ```json
   {
     "dev.containers.dockerPath": "podman",
     "dev.containers.mountWaylandSocket": false
   }
   ```
   The second one is needed on hosts with WSLg (Windows 11): otherwise the extension adds a bind mount of the
   WSLg socket that Podman rejects ("unsupported UNC path"). Not checked: whether a host without WSLg
   needs it.

### Windows (tested)

- Windows 11 or later with hardware virtualisation enabled. A Podman machine is backed by **WSL 2 or Hyper-V**;
  Hyper-V is not available on Windows Home, and creating the first Hyper-V machine needs administrator rights
  (`podman system hyperv-prep` can pre-configure permissions; [Podman for Windows](https://github.com/podman-container-tools/podman/blob/main/docs/tutorials/podman-for-windows.md)).
  WSL 2 is therefore still needed (or Hyper-V); the container does not remove that requirement, the Podman
  machine hides it.
- Tested: the machine that Podman Desktop created, WSL provider. On that host it was **already rootful**. A machine
  created with the plain `podman machine init` is rootless by default according to the Podman tutorial; to switch,
  stop it, run `podman machine set --rootful`, start it again, and re-check with the command above. Rootful and
  rootless storage are separate, so existing images and containers disappear from the default connection.
- Not tested: the Hyper-V provider, a freshly created machine, hosts without WSLg.

### Linux (not tested)

> **TODO(native Linux tester):** test the container on a native Linux host and replace this section. No Linux checklist exists yet; the Windows checklists in `openspec/changes/archive/2026-10-07-add-podman-devcontainer/` are the template.

Expected approach, based on documentation only: a rootful Podman machine. The
[Podman reference](https://docs.podman.io/en/latest/markdown/podman-machine.1.html) lists `qemu` as the Linux
provider and says a machine "can be optionally used on Linux". That would match the tested Windows setup: the
`podman` command on your host talks to a rootful VM, so the VM is the boundary.

Fallbacks, all untested and **root-equivalent for your own account** because no VM separates the container from
your host: a rootful Podman socket, or a wrapper script behind `dev.containers.dockerPath` that runs
`sudo podman`. The extension setting is described as "an executable name or path", so a wrapper script is a legitimate value but the
setting probably cannot carry arguments; neither point was tried.

### macOS (partly tested)

> **TODO(macOS tester):** try Azure and the VS Code UI on macOS and record the results here.

Tried on macOS 26.7.1, Apple Silicon, Podman 6.1.3 with the applehv provider. Intel Macs were not tried.

1. Podman on macOS always uses a machine, and a machine created with `podman machine init` is **rootless**. Make
   it rootful (rootful and rootless storage are separate, so images pulled before do not carry over):
   ```
   podman machine stop
   podman machine set --rootful
   podman machine start
   podman info --format "{{.Host.Security.Rootless}}"   # must print false
   ```
   Afterwards the default connection is `podman-machine-default-root`; `podman system connection list` shows it.
2. Give the machine enough memory. The default of 2 GiB is too small: `devcontainer-minikube-start` alone asks
   for 4 GiB. 8 GiB was used here; no minimum was measured.
   ```
   podman machine stop && podman machine set --memory 8192 && podman machine start
   ```
3. The image builds natively for arm64 (the Dockerfile picks the download for `uname -m`). Do not build it for
   x86_64 under emulation.

Without VS Code, the [Dev Containers CLI](https://github.com/devcontainers/cli) uses the same `devcontainer.json`
(it ignores the VS Code extensions and does not forward ports):
```
npx @devcontainers/cli up --workspace-folder . --docker-path podman
npx @devcontainers/cli exec --workspace-folder . --docker-path podman bash
```

Run `podman compose` and the helper commands **inside** the container. The macOS host has no compose provider,
and `podman compose` on the host fails with "looking up compose provider failed".

## Opening the container

1. Open the repository folder in VS Code.
2. Command Palette: **Dev Containers: Reopen in Container**. The first build takes a few minutes (about 3 minutes
   for the image on a Linux host; the Windows time was not recorded).
3. Check the automatic setup in a terminal inside the container:

   | Command | Expect |
   |---|---|
   | `cat /proc/self/cgroup` | `0::/init` |
   | `devcontainer-healthcheck-runner status` | `running (pid N)` |
   | `podman run --rm docker.io/library/alpine:3.20 echo nested-ok` | `nested-ok` |
   | `podman compose version` | `podman-compose version 1.6.0` |
   | `git rev-parse --short HEAD` | a commit id, no "dubious ownership" error |
   | `df -h /dev/shm` | `1.0G` |

Closing the VS Code window **stops** the container; reopening starts it again and the setup above reruns by
itself. If the container is restarted behind VS Code's back (for example `podman restart`), the connection drops;
reload the window (**Developer: Reload Window**) and the runner and cgroup setup come back.

## Everyday use

**Secrets and `.env`.** On first creation, if `.env` or `secrets/auth-rs256-private-key.pem` is missing it is
generated (random passwords, a fresh key). Existing files are never overwritten. If you opened a local folder,
the container sees the checkout on your host, **including your own gitignored `.env`, key and Terraform state**,
and uses them unchanged. Every process in this privileged container can read them.

**Compose stack.**
```
podman compose up -d        # services start after PostgreSQL reports healthy
podman compose ps
podman compose down
```
The Spring services need some seconds after `up -d` before their health endpoints answer (auth-service took 14 s
in one run). Open `http://localhost:8080` in your host browser.

**End-to-end tests.** With the stack running, from the repository root:
```
devcontainer-install-playwright          # once; about 40 s on a Linux host, safe to repeat
cd e2e && npm run test:e2e
```
`npx playwright install --with-deps` does **not** work here (it uses `apt-get`; the image is Fedora). On
Windows the suite gave 18 passed and 1 skipped. One test skips itself: "date-range filter with future dates shows no
results" (seen on macOS, 5 of 5 runs), because the From/To `<label>`s in `frontend/src/pages/HistoryPage.tsx` are
not associated with their inputs, so `getByLabel` finds nothing. Which test skipped on Windows was not recorded.

**minikube.** Stop the compose stack first (both use port 8080 and a lot of memory), then:
```
devcontainer-minikube-start
./scripts/deploy-minikube.sh             # the repo's script, unchanged
```
Then follow the main README for the port-forward. The deploy took 420 s (Windows) and 427 s (Linux) in earlier
runs with a throwaway image.

**Azure and Terraform.** `az login --use-device-code` works. Login state lives in a named volume and survived a
container rebuild (`az account show` still worked without logging in again; reported by a teammate on Windows).
`terraform init -backend=false && terraform validate` succeeds in `infra/terraform/stages/dev`; `plan` and
`apply` were not run. `deploy-azure.sh` finds `docker` (Podman) and `git`; the login, build and push steps were
not run.

**Named volumes** keep these across rebuilds: nested Podman storage, the Maven cache, Azure CLI and kubeconfig
state, minikube data, and `node_modules` for `frontend/` and `e2e/`. They are named after the devcontainer id;
remove them with `podman volume rm` when you no longer need them.

## Where this differs from the main README

- Start minikube with `devcontainer-minikube-start`, not plain `minikube start`: inside the container it needs
  `--driver=podman`, `--container-runtime=containerd` and `--force`.
- The README's troubleshooting row for `ImagePullBackOff` suggests `eval $(minikube docker-env)`. That does not
  apply: `scripts/deploy-minikube.sh` builds with `minikube image build`.
- Do not install `docker-compose`. On Fedora it also installs a shim that calls `docker compose`, which calls
  `podman compose`, which calls the shim again; this exhausted the container's process limit in the spike.
- The compose stack and the minikube port-forward both use port 8080, so run one at a time.

## Resources

Indicative single readings, not requirements; **no minimum has been determined**.

| Measurement | Value | Host |
|---|---|---|
| Memory with minikube and the application running: working set (`anon`) | 2.70 GB | Windows |
| Same: page cache (`file`, reclaimable) | 4.17 GB | Windows |
| Same: what `podman stats` showed (mixes both) | 5.04 GB | Windows |
| Nested container storage after minikube and the application | 7.4 GB | Linux and Windows (earlier runs) |
| Devcontainer image | 2.24 GB | Linux build |
| Windows Podman machine disk in use after the test | 8.8 GB (not a dedicated spike machine) | Windows |

To read memory yourself inside the container: `grep -E '^(anon|file|shmem) ' /sys/fs/cgroup/memory.stat`.
Compose images build from source: 495 s in one Windows run (cache state not recorded) and about 13 minutes on a
cold Linux build, mostly Maven downloads.

## Security

The container is **privileged** and its engine is **rootful**, because it runs Podman and minikube inside itself.
Anything running in it has root-level control of that engine. On Windows (tested) and macOS (expected, untested) the boundary is the Podman
machine VM. On Linux without a VM (the untested fallbacks above) it is your own host. Do not open repositories you
do not trust in this container. Podman's own documentation warns that its API socket "allows arbitrary code
execution as the user running the API".

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `cat /proc/self/cgroup` prints `0::/`, or minikube fails with `open memory.max ... No such file` | The cgroup setup did not run. Run `devcontainer-cgroup-init` and open a new terminal. |
| VS Code loses the connection after a `podman restart` | Reload the window. |
| `unsupported UNC path` when the container starts | Set `dev.containers.mountWaylandSocket` to `false`. |
| On minikube, about 2 in 5 requests through the ingress hang; ingress-nginx logs `pthread_create() failed (11: Resource temporarily unavailable)` and `worker process ... cannot be respawned` | The minikube node was created with Podman's default pids limit, so every pod container is capped at 307 threads, and ingress-nginx exceeds that on a config reload when the machine has several CPUs (5 on the Mac where this was seen). `.devcontainer/containers.conf` sets `pids_limit = 0`; in an older container, rebuild it, then `minikube delete` and `devcontainer-minikube-start`. Check with `minikube ssh -- systemctl show --property DefaultTasksMax` (307 is the bad value). |
| `podman compose up -d` hangs, or the Spring services stay `Created` | Podman is not running the health checks. `devcontainer-healthcheck-runner status`; start it with `devcontainer-healthcheck-runner start`; read the log. |
| `git`: "detected dubious ownership" | `git config --global --add safe.directory "$PWD"` (the first-creation step normally does this). |
| e2e tests fail with text "hidden" and screenshots without text | Fonts are missing. Run `devcontainer-install-playwright` again. |
| e2e tests fail with "Target page, context or browser has been closed" | `/dev/shm` is too small. `df -h /dev/shm` must show `1.0G`; if not, recreate the container (**Dev Containers: Rebuild Container**) so the `runArgs` apply. |
| Images and containers vanished after `podman machine set --rootful` | Rootful and rootless storage are separate. Switch back, or rebuild in the rootful one. |
| Hyper-V machine cannot be created | Needs administrator rights for the first machine; `podman system hyperv-prep` can pre-configure permissions (Podman for Windows tutorial). Untested here. |

## Repository in a volume (untested)

**Dev Containers: Clone Repository in Container Volume** would keep the checkout inside the container, so none of
your host files, including secrets, would be visible, and file access should be faster than on a Windows folder
(not measured). It has not been tried with Podman. The extension appears to use `dev.containers.dockerSocketPath`
(default `/var/run/docker.sock`) for this flow.

> **VERIFY:** whether it works with Podman, and which socket path it needs (`/run/podman/podman.sock` is a guess).

## Known gaps

- Native Linux: untested. macOS: partly tested (above).
- The repository-in-a-volume flow.
- Helm: no dedicated VS Code extension is installed; the Kubernetes extension is, and whether it covers Helm charts was not checked.
- `devcontainer.json` `runArgs` (`--shm-size=1g`) and the fonts fix were confirmed by the Windows run; 1 GB is the tested size, not a measured minimum.
- Node 20, the version the project uses, may be past its end of life (from memory, unverified); not changed here.
