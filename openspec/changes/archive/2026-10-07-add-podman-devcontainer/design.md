## Context

Beer Tracker is a compose stack (PostgreSQL 16, four Spring Boot 3.3.4 services on Java 21, nginx, a React/Vite frontend on Node 20), with Helm charts for minikube and AKS and Terraform for Azure. The README documents three scenarios (compose, minikube, AKS) and lists tool prerequisites, but nothing provisions them.

Facts from the repo that constrain the design:

- `scripts/deploy-minikube.sh` builds with `minikube image build` and notes that `minikube docker-env` does not work with the Podman CLI, so that path is already engine-neutral.
- `scripts/deploy-azure.sh` calls `docker login`, `docker build` and `docker push` literally, and `git rev-parse --short HEAD` for the image tag.
- `docker-compose.yml` uses short image names (`postgres:16-alpine`, `nginx:alpine`), `depends_on: condition: service_healthy`, and bind-mounts `./secrets/auth-rs256-private-key.pem` and `./nginx/nginx.conf`.
- `.env`, `secrets/*.pem` and `*.tfstate` are gitignored and untracked.

Constraints from the team: Podman is the standard engine; hosts are Windows, macOS and Linux; a privileged devcontainer is acceptable; minikube must run inside the devcontainer; no AI-agent tooling in the image.

## Goals / Non-Goals

**Goals:**
- One devcontainer from which a developer can run unit tests, the compose stack, the Playwright e2e suite, the minikube deployment and the Azure deployment scripts.
- Works on Windows, macOS and Linux hosts with the same `devcontainer.json`.
- No real secret ever enters the image or is copied from the host.
- Known risks are retired by an explicit spike, not assumed away.

**Non-Goals:**
- No change to application code, charts, Terraform, `docker-compose.yml` or the deploy scripts.
- No Docker support or Docker fallback.
- No Claude Code, openspec CLI or `gh` in the image (can be added later as features).
- No CI pipeline (`.github/workflows/` is currently empty).
- No fixing of the stale `docker-env` README row.
- Not choosing an alternative to minikube; that is a team decision if the spike fails.

## Decisions

**D1. Image built from a Dockerfile, not assembled from devcontainer features.**
Podman is not available as a standard feature, and it needs tuned configuration (`registries.conf`, storage, subuid/subgid). A Dockerfile keeps all of that in one reviewable place. Alternatives: stacking features on a stock Java image (rejected: Podman would still need a custom layer, so two mechanisms); starting from `quay.io/podman/stable` (the candidate base; it ran nested minikube and the unchanged deploy script on Linux and on Windows. A Debian-based alternative was not tried. The full toolchain now builds on it (`.devcontainer/Dockerfile`, 3m14s, 2.24 GB image, one run). Findings from that build: **Fedora 44 has no JDK 21 package** (only JDK 25 and an early-access 27), so JDK 21 is an Eclipse Temurin tarball (release `jdk-21.0.12.1+1`, checksum from the Adoptium API), the same distribution as the services' `eclipse-temurin-21` images. Maven 3.9.16, Node v20.20.2, Terraform 1.16.1, minikube, kubectl and helm are checksum-verified release artefacts; the Azure CLI 2.91.0 comes from Microsoft's RHEL 9 RPM repository and installed on Fedora 44; the PostgreSQL client is the distro's (18.6, newer than the server image's 16). Distro packages (Podman, compose provider, PostgreSQL client) float with the base image's Fedora release. Trade-off accepted for now: a Fedora base means any further tool that is not packaged there needs the same tarball treatment.
>
> **VERIFY:** Node 20 may be past its end of life (its latest release here is dated March 2026; from memory its support ended in April 2026). The repo's frontend image also uses `node:20-alpine`. Out of scope for this change, but the team should know.

**D2. Privileged devcontainer with Podman running inside it, launched by a rootful host Podman.**
Accepted by the team, including rootful host Podman as a prerequisite (decided after the Linux spike: nested minikube worked on a rootful host and did not on a rootless one). The outer container needs a cgroup v2 fix so nested Podman can create cgroups with controllers. The chosen approach is an init step that moves every process in the container's cgroup into an `/init` sub-cgroup and enables the controllers (spike variant B), because nested workloads then stay accounted to the outer container. **The init step runs from `postStartCommand`, not as PID 1:** the Dev Containers extension appends its own `--entrypoint /bin/sh` after any `runArgs` entrypoint, so an entrypoint override does not survive (observed on Windows with VS Code 1.140.0 and Dev Containers 0.469.0). Run as `spike-init.sh /bin/true`, the script does the cgroup setup and exits; processes started afterwards by VS Code land in `/init` and nested minikube works (one run, Windows). The script must stay safe to run on every container start. Required companion setting on hosts with WSLg: the user setting `dev.containers.mountWaylandSocket = false`, because the extension's WSLg socket bind mount is rejected by Podman ("unsupported UNC path"); it has application scope, so `devcontainer.json` cannot carry it and the host-setup guide must. Fallback to the init step: `--cgroupns=host` in `runArgs`, which also worked on Linux but appears to put nested containers outside the outer container's cgroup (inference, see Spike Findings). Alternative: mount the host Podman socket (rejected: bind-mount paths would resolve on the host, reintroducing path inconsistencies, and the container would control the host engine).

**D3. minikube runs inside the container with `--driver=podman`.**
Required by the team. It keeps README scenario 2 working unchanged. A VM-based driver is rejected because it would need nested virtualisation. On a rootful host with the D2 cgroup fix a plain start (`--driver=podman --container-runtime=containerd --force`) worked in the spike; the `KubeletInUserNamespace` feature gate is only needed for rootless hosts, which are not supported. `--force` is required because minikube runs as root inside the container. The README's plain `minikube start` is not sufficient; the devcontainer needs a documented or wrapped start command.

**D4. `podman-docker` provides the `docker` command.**
`deploy-azure.sh` calls `docker` literally, and a shell alias would not be seen by a non-interactive script. Alternative: add an engine variable to the script (rejected here: script change outside scope).

**D5. One compose provider: `podman-compose`.**
Decided after task 1.3, on the team's stated preference and the Windows run below. `podman compose` delegates to an external provider, and if both `docker-compose` and `podman-compose` are installed, `docker-compose` wins by default. In the Windows run (Podman 5.8.7 inside the container, `podman-compose` 1.6.0, `docker-compose` 5.5.1) both providers honoured `depends_on: service_healthy` once something executed the health checks, and neither did without it. `podman-compose` needs nothing else; `docker-compose` also needs the Podman API socket started by hand. A further reason to drop `docker-compose`: on Fedora 44 `dnf install docker-compose` pulls in `docker-compose-switch`, whose `/usr/bin/docker-compose` shim calls `docker compose`, which calls `podman compose`, which selects the shim again, a loop that exhausted the container's process limit in the spike. The image therefore installs only `podman-compose`, which `podman compose` then selects without any setting (checked in the built image). It is pinned only by the base image's Fedora package (1.6.0 at the time of the spike). Untested: `podman-compose` on a native Linux host or macOS, and its full-stack HTTP result (ports 8083 and 8084 returned `000` 15 s after `up` in the Windows run; cause not established, the test kit now polls instead).

**D7. Short image names resolved through `registries.conf`.**
Set `unqualified-search-registries` to `docker.io` so the compose file works unmodified. Alternative: qualify names in the compose file (rejected: changes a file outside scope).

**D8. Secrets are generated, never copied.**
The lifecycle step runs `openssl genrsa` for `secrets/auth-rs256-private-key.pem` and copies `.env.example` to `.env` if absent. Nothing is baked into the image and `devcontainer.json` adds no host mount except named volumes (checked: no bind mounts, build context is `.devcontainer/` only). **Scope decided by the team:** the requirement covers what the devcontainer itself adds. In a bind-mounted checkout the developer's own gitignored `.env`, key and Terraform state are visible to the container and are used unchanged (the Windows run confirmed that `post-create` left the host's `.env` and key in place); the host-setup guide must say so. The repo-in-volume flow (D6) remains an option that avoids this, but it is not required. The Azure CLI login uses device code flow, with state kept in a named volume.

**D9. Playwright browsers are opt-in, through a helper.**
The browser is not in the image. `npx playwright install --with-deps chromium`, as first planned, **does not work here**: `--with-deps` installs libraries with `apt-get`, and this image is Fedora (observed: "your OS is not officially supported ... installing dependencies for ubuntu24.04-x64 as a fallback", then `apt-get: command not found`, exit 1). Without `--with-deps` the headless Chromium of Playwright 1.62.1 downloads fine but lacked 16 shared libraries, which map to 16 Fedora packages (`alsa-lib at-spi2-atk at-spi2-core atk dbus-libs libX11 libXcomposite libXdamage libXext libXfixes libXrandr libxcb mesa-libgbm nspr nss nss-util`). `devcontainer-install-playwright` installs those with `dnf`, installs the browser, and fails loudly if `ldd` still reports missing libraries. Tested in the built image: a fresh run takes about 40 s, a second run is a no-op, and a headless launch plus `setContent` works. **Not tested:** the e2e suite itself against the running stack (fonts, timing). **Shared memory:** `devcontainer.json` sets `runArgs: ["--shm-size=1g"]`. With Podman's default 64 MB `/dev/shm`, headless Chromium crashed on the dashboard and 15 of 19 e2e tests failed; after remounting `/dev/shm` at 1 GB (and with fonts installed) the suite gave 18 passed and 1 skipped (Windows, single run). 1 GB is the size that was tested, not a measured minimum. The helper also installs fonts (`liberation-fonts`, `dejavu-sans-fonts`): without any font, Playwright treats text elements as hidden (see the Windows verification below). A newer Playwright may need other libraries; the helper's final check reports them. The e2e README's own command (`npx playwright install chromium`) is the same minus the libraries.

**D10. Minimum versions follow the README.**
Helm >= 3.10, minikube >= 1.32, Terraform >= 1.9, Azure CLI >= 2.60, Podman >= 4 (README minimum). For the **host**, the only tested combination with VS Code is VS Code 1.140.0, Dev Containers 0.469.0 and Podman 6.0.2 on Windows; the VS Code documentation says Podman 5+, and Podman 4.9.3 was tested on Linux only without VS Code. The host-setup guide must state a tested minimum, which is not yet established. Java 21 and Node 20 follow the poms and Dockerfiles; Maven 3.9 follows the build image tag.

**D11. Health-check runner started from `postStartCommand`.**
Without systemd inside the container nothing executed Podman health checks in the spike (zero executions of the PostgreSQL check on both hosts when no runner was present), so `depends_on: service_healthy` waited forever. The Podman reference pages I read say nothing about how checks are scheduled, so this rests on our own observations. Chosen mechanism: `devcontainer-healthcheck-runner start` (`.devcontainer/scripts/healthcheck-runner.sh`), an idempotent background loop that runs `podman healthcheck run` for every container that has a health check, started from `postStartCommand` after the cgroup init. Systemd as PID 1 is not an option because the extension replaces the entrypoint. **Verified:** the script's mechanics on a Linux host (start is idempotent, `status` and `stop` work, only health-checked containers are selected, no stray processes); the effect of the same command as a loop in the Windows runs (runs 2 and 5). **Not verified:** the runner itself inside the no-systemd container (the host used for the script test already ran health checks automatically, so it could not show the effect), surviving a VS Code reconnect, and restarting with the container. It ignores each container's `--health-interval` and polls every 5 s. The Podman API socket is no longer needed, because the chosen provider does not use it.

- [minikube podman driver may not run nested in a privileged container] → Spike first, on all three host types. If it fails, escalate to the team; kind/k3d would change `deploy-minikube.sh`, `values-minikube.yaml` and the README and is out of scope here. **Resolved 2026-10-07: go** on the tested hosts, see "Go/no-go on nested minikube".
- [Compose provider may not honour `service_healthy`] → Spike acceptance criterion; choose the provider that passes.
- [Rootful host Podman is now a prerequisite on every host OS] → Document it in the host-setup guide; for Windows and macOS the Podman machine must be rootful. `podman machine set --rootful` is documented; on the tested Windows host (Podman Desktop) the default machine was already rootful, but a machine created with the plain CLI is rootless by default according to the Podman tutorial, so the guide must tell developers to check `podman info --format "{{.Host.Security.Rootless}}"` for `false`. A freshly created machine and `set --rootful` were not exercised on Windows. Linux hosts: see the Linux launch findings.
- [Windows needs Podman machine, hence WSL2 or Hyper-V and possibly admin rights] → Document in the host-setup guide; state plainly that WSL2 is not eliminated, only hidden.
- [Memory and disk for the stack plus minikube is unmeasured] → Measure in the spike and record the numbers; do not publish estimates before then.
- [Privileged container weakens isolation from the host] → Accepted by the team; document it.
- [Host-side launch differs per OS (for example the VS Code Dev Containers Podman setting, user-namespace flags)] → Windows verified in the spike (see "Task 1.1 follow-up"): `dev.containers.dockerPath = "podman"`, `dev.containers.mountWaylandSocket = false`, and the cgroup init through `postStartCommand`. Linux rootful and macOS are not verified; record each in the host-setup guide.
- [Repo in a volume hides files from host tools] → Document; developers edit through the IDE attached to the container.

## Spike Findings

### Linux (WSL2 distro, native rootless Podman 4.9.3), 2026-10-07

Candidate A: `quay.io/podman/stable` (Podman 5.8.7, Fedora) plus `podman-docker`, `podman-compose`, `docker-compose` 5.5, host copies of minikube 1.38.1, kubectl 1.34.1 and helm 4.3.0. Outer container run `--privileged --user root` with a named volume on `/var/lib/containers`. Single host, single run; one data point, not a benchmark.

| Check | Result |
|---|---|
| Nested `podman run` | Works (rootful inside, overlay driver, crun). |
| `docker` resolves to Podman | Works via `podman-docker`. |
| Compose stack (images built, all endpoints 200) | Worked, but only under the base image's `containers.conf` that forces host namespaces. **Not yet re-verified** with the corrected config. |
| `depends_on: service_healthy` | **Does not work out of the box.** Podman runs health checks via systemd timers; with no systemd, health stays `starting` with no runs and compose waits indefinitely. A loop running `podman healthcheck run` unblocked it. |
| Compose provider | `docker-compose` 5.5 needs the Podman API socket (`podman system service`) started by hand. `podman-compose` not yet tested. |
| minikube `--driver=podman` | **Fails with the base image's `containers.conf`** (`utsns="host"`: "cannot set hostname when running in the host UTS namespace"). With a minimal replacement config it then fails at the kubelet (`/proc/sys/vm/overcommit_memory: permission denied`) because the host Podman is rootless. **Starts in 22 s** with `--force --feature-gates=KubeletInUserNamespace=true`. |
| `deploy-minikube.sh` unchanged | **Not passing.** (a) Pre-existing repo defect: the charts consume `beer-tracker-secrets`, the script creates four per-service secrets, so pods stay in `CreateContainerConfigError`. `scripts/set-k8s-secrets.sh` also uses a different key set from `deploy-azure.sh`. (b) With the secret created by hand in the throwaway cluster, services crash with `UnknownHostException: postgresql`: pods cannot reach each other or CoreDNS (direct query to the CoreDNS pod IP times out; CoreDNS upstream `192.168.49.1:53` also times out). |
| Image gaps | `openssl` and `pgrep`/`ps` are missing from the base image. |

Unconfirmed lead for the pod networking failure: the node reports `-P FORWARD DROP`. Kernel modules `br_netfilter`, `ip_tables` and `nf_conntrack` are present and `bridge-nf-call-iptables` is 1. Not tested: other CNI settings, a rootful host Podman, or a `podman system service`-free setup.

Measured (compose stack running, indicative only): whole devcontainer about 1.45 GB memory; `/var/lib/containers` 4.1 GB including 50 build layers (89% of image data reclaimable). minikube figures not taken because the cluster never ran the workload. Windows and macOS not tested.

### Linux (WSL2 distro), rootful host Podman 4.9.3, cgroup v2, 2026-10-07

Same candidate image, outer container run from `sudo podman`. Two scripts, three runs; each single-shot.

| Check | Result |
|---|---|
| minikube, plain start (`--driver=podman --container-runtime=containerd --force`, **no** feature gate) | First attempt failed: `crun: open 'memory.max' ... No such file or directory`. Cause (hypothesis, consistent with both variants): the outer container's cgroup holds processes, so cgroup v2 cannot delegate controllers to nested cgroups. |
| Variant A: outer container `--cgroupns=host` | minikube exit 0, node Ready, pod DNS works (resolved `github.com` via CoreDNS at `10.96.0.10`), node `FORWARD` policy is ACCEPT. `podman exec` works. Whole-container memory read **3.0 MB** with an idle cluster, so the nested containers appear to live **outside** the outer container's cgroup (inference from the number; limits on the outer container would not constrain them). |
| Variant B: PID 1 moves into a `/init` sub-cgroup and enables controllers (DinD-style) | Same results; `podman exec` works afterwards (process lands in `/init`). Whole-container memory **444 MB** with an idle one-node cluster (single reading), so nested workloads are accounted to the outer container. |

Not visible in the log: the result of the `kubernetes.default.svc.cluster.local` lookup (output was clipped by `tail`); only the `github.com` lookup through the same CoreDNS service is shown.

Summary across host modes: nested minikube works on a **rootful** host Podman with a cgroup fix, without `KubeletInUserNamespace`; on a **rootless** host it needs that flag and pod networking still fails (node `FORWARD` policy DROP; cause not established). Whether the rootless failure can be fixed was not investigated further.

#### End-to-end run, rootful host, variant B (2026-10-07)

Working tree at `c0d9ef9` plus 11 uncommitted files (including the fix for the `beer-tracker-secrets` mismatch in `deploy-minikube.sh`), copied into the container without `.env`, key or tfstate; throwaway secrets generated inside. Single run.

| Check | Result |
|---|---|
| `minikube start -p spike --driver=podman --container-runtime=containerd --memory=4096 --force` (no feature gate) | exit 0 in 23.6 s, node Ready |
| `scripts/deploy-minikube.sh` unchanged (`MINIKUBE_PROFILE=spike` set in the environment only) | exit 0 after 427 s, including five in-cluster image builds |
| Pods | auth, tracking, notification, statistics, frontend and postgresql all `1/1 Running`, 0 restarts |
| Ingress via port-forward | `/auth/.well-known/jwks.json` 200; `/statistics/` and `/tracking/` 401 (no token); `/` returned the frontend HTML on the second request. **Unexplained:** first `/` request and `/notifications/` returned `000` (no HTTP response). Likely a port-forward race for `/`; not established for `/notifications/`. |
| Memory, outer container, full app | 1.81 GB, 1.815 GB 60 s later (idle cluster alone read 444 MB earlier). Indicative, one 16 GB host. |
| Disk, `/var/lib/containers` | 7.4 GB, including build layers |

Not functionally tested: login, recording a drink, any API behaviour beyond the status codes above.

Still not tested in rootful mode: compose health-check ordering with the corrected `containers.conf` (the no-systemd health-check problem seen earlier is expected to recur), VS Code attaching to the container, Windows and macOS.

### Host launch: documentation lookup for Windows (task 1.1, accessed 2026-10-07)

Read, not tested. Sources: [VS Code, Alternate ways to install Docker (Podman section)](https://code.visualstudio.com/remote/advancedcontainers/docker-options), [Podman for Windows tutorial](https://github.com/podman-container-tools/podman/blob/main/docs/tutorials/podman-for-windows.md), [podman-machine-set reference](https://docs.podman.io/en/latest/markdown/podman-machine-set.1.html), [Podman discussion #25607, Podman with Dev Containers on WSL2](https://github.com/podman-container-tools/podman/discussions/25607) (community discussion, Podman Machine on WSL2, dated March 2025, updated May 2026; not an official source).

| Question | What the sources say |
|---|---|
| How does VS Code use Podman? | Set `dev.containers.dockerPath` to `podman` (stated for Linux, Windows and macOS). The page says Podman 5+ is "mostly compatible" with Docker CLI commands, and that `podman compose` needs a compose provider. It gives no OS-specific, rootless or rootful guidance and lists no limitations. |
| Windows prerequisites | Windows 11 or later, hardware virtualisation enabled. A Podman machine is backed by WSL 2 or Hyper-V; Hyper-V is not available on Windows Home. First Hyper-V machine init needs administrator rights, and `podman system hyperv-prep` can pre-configure permissions so later use does not. WSL and Hyper-V machines cannot run at the same time (from search results). Which provider is the default is not stated clearly in the page I read. |
| Rootful machine | Default is rootless "for behavioral consistency with Podman on Linux". `podman machine set --rootful` switches it; the tutorial says to stop the machine first, the reference page does not mention that. Rootful and rootless storage are separate, so existing images and containers disappear from the default connection after switching. The reference page does not say which providers support the option. |
| `--userns=keep-id` | Recommended in the community discussion as a **rootless** permission workaround in `runArgs`. With a rootful machine (our decision D2) it is probably unnecessary; not tested. |
| Other WSL2 notes from the discussion | Enable cgroup v2 in `.wslconfig` (`kernelCommandLine = cgroup_no_v1=all`) to fix `podman stats` errors; a shared-mount remount workaround that does not persist across `wsl --shutdown`; a maintainer is quoted as saying Podman does not work with systemd enabled in WSL (unclear whether that applies to a Podman machine or a self-managed distro). |

Consequences for this design:
- Confirmed: `dev.containers.dockerPath = "podman"` is the documented setting, and `podman machine set --rootful` exists. Both were previously from memory.
- **Version conflict:** the VS Code page says Podman 5+; the README says Podman >= 4. The spike host ran 4.9.3 but never used VS Code. The host-setup guide must state a tested minimum; open.
- Our `devcontainer.json` is a single image, not a compose file, so the extension's compose provider setting should not be needed for the devcontainer itself (inference; not tested).
- The D2 cgroup init step assumes a cgroup v2 hierarchy inside the Podman machine VM. The discussion suggests WSL2 may need v2 enabled explicitly, so the Windows spike must check the filesystem type of `/sys/fs/cgroup` before relying on it.
- The path convention for mounting Windows folders is documented, but our design clones the repo into a volume, so it is not exercised.
- Not found in these sources: how VS Code launches a **rootful** Podman on a Linux host (a `sudo` wrapper, or a rootful socket); not researched and probably the hardest launch question.
- The search also surfaced open issues in the `vscode-remote-release` repository about Dev Containers failing with Podman on specific VS Code versions (titles only, not read). The guide will need to name a tested VS Code and Podman version pair.
- macOS deferred by decision; not researched.

### Host launch: documentation lookup for Linux with a rootful Podman (task 1.1, accessed 2026-10-07)

Read, not tested. Sources: [podman-system-service reference](https://github.com/podman-container-tools/podman/blob/main/docs/source/markdown/podman-system-service.1.md), [Podman discussion #12903, rootful backend with an unprivileged user](https://github.com/containers/podman/discussions/12903) (January 2022, community), [vscode-remote-release #4643](https://github.com/microsoft/vscode-remote-release/issues/4643) (2021, closed, resolution not visible to me) and [#10814](https://github.com/microsoft/vscode-remote-release/issues/10814) (March 2025, open, rootless setup with `dev.containers.dockerSocketPath`), plus the VS Code page cited above.

What is established:
- The rootful API socket defaults to `/run/podman/podman.sock` (rootless: `$XDG_RUNTIME_DIR/podman/podman.sock`), and it can be provided on demand through systemd socket activation.
- Podman's documentation warns that API access "allows arbitrary code execution as the user running the API, with no ability to limit or audit this access". For a rootful socket that means root on the host.
- A Podman discussion shows an unprivileged user using a rootful socket after changing the socket group and permissions; a maintainer comment in it likens this to recreating the Docker daemon, and the manual permission change does not persist across restarts (a systemd-managed group is the suggested alternative).
- Dev Containers extension 0.469.0, `package.json` (read locally, 2026-10-07): `dev.containers.dockerPath` is "Docker (or Podman or WSLc) executable name or path" (string, default `docker`, application scope), so a path to a wrapper executable is a legitimate value, but it cannot carry arguments; `dev.containers.dockerComposePath` defaults to `docker-compose`; `dev.containers.dockerSocketPath` (default `/var/run/docker.sock`) is documented only as "Used, e.g., when connecting to a Dev Container with the devcontainer.json in a Docker Volume", not as a general engine selector. **Implication for D6** (repository in a volume): that flow uses the socket path, so on Podman it probably has to be set to the engine's socket (inside a Podman machine, a rootful `/run/podman/podman.sock` per the system-service reference). Not tested; the Windows run did not exercise D6.
- [podman-machine reference](https://docs.podman.io/en/latest/markdown/podman-machine.1.html): lists "Linux | qemu*" in its table of providers by platform (asterisk = default), and says a machine "can be optionally used on Linux". Supported in the documentation; not tested by us.

What is **not** established, and was not found in official documentation:
- Any supported way for the Dev Containers extension to drive a rootful Podman on Linux. The VS Code page gives no rootful or rootless guidance.
- Whether the extension accepts a wrapper script (for example one that runs `sudo podman "$@"`) as `dev.containers.dockerPath`, or works with Podman's remote client against a rootful socket. #4643 reports a Podman-over-SSH failure in 2021; its outcome is not visible in what I read.
- Whether a Podman machine works in practice on a Linux host as an alternative that matches the Windows and macOS setup. It is documented (qemu provider); it was not run. The spike host (a WSL2 distro) has `/dev/kvm` but no QEMU installed and is not representative of a native Linux laptop, so this needs a native Linux tester. Unknown: the machine's default memory (it must be raised for minikube plus the app; no measured requirement exists) and the `/dev/kvm` access it needs.

Candidate launch paths for Linux, all untested:

| Path | What it needs | Concern |
|---|---|---|
| A. `dockerPath` pointing to a wrapper that calls `sudo podman` | Passwordless sudo for `podman` | Root-equivalent for the user; whether the extension tolerates a wrapper is unverified. |
| B. Rootful socket plus `podman --remote` (`CONTAINER_HOST`) | `podman.socket` enabled as root, socket group access | Root-equivalent via the socket; extension compatibility with the remote client is unverified. |
| C. Podman machine on Linux (qemu), set rootful | QEMU and `/dev/kvm` access on the host; documented as supported, untested | Extra VM and its memory; would be the same arrangement as the tested Windows setup (host CLI talking to a rootful VM), bounding the blast radius to the VM and avoiding sudo and socket-group changes. Leading candidate, pending a native Linux test. |
| D. Launch with the `devcontainer` CLI under `sudo`, attach with another client | Not researched | Loses the normal VS Code reopen-in-container flow. |

Implication: the rootful prerequisite chosen after the Linux spike is, on a Linux host, effectively root-level access for the developer, whereas on Windows and macOS the Podman machine VM is the boundary. Whether the team accepts that for Linux hosts has not been asked explicitly.

### Windows host, Podman Desktop WSL machine, 2026-10-07

Host: Windows 11 Enterprise 10.0.26200, Podman 6.0.2 (Podman Desktop), the existing `podman-machine-default` (WSL provider, created by the default setup, **not** a dedicated spike machine). Its default connection was already the rootful one (`podman-machine-default-root`). Same spike image as the Linux rootful runs, built unchanged. Candidate A only; single runs, one host.

| Check | Result |
|---|---|
| `podman info` rootless | `false`, with no `podman machine set --rootful` needed |
| cgroup type in the machine | `cgroup2fs`, so no `.wslconfig` change was needed |
| Image build | OK |
| `/proc/self/cgroup` in the container | `0::/init` |
| Nested `podman run`, `docker` resolves to Podman | `nested-ok`; `docker --version` prints `podman version 5.8.7` |
| `minikube start` (plain, `--force`, no feature gate) | exit 0, node Ready; 105 s end to end in the first run, 71.8 s from the VS Code terminal. Linux was 23.6 s. Cause of the difference not established (image pulls are one candidate, not checked) |
| `scripts/deploy-minikube.sh` unchanged | exit 0 after 420 s; six pods (auth, tracking, notification, statistics, frontend, postgresql) `1/1 Running`, 0 restarts |
| Ingress probe, two passes | Pass 1: `/` 200, `/auth/.well-known/jwks.json` 200, `/statistics/` 401, `/tracking/` 401, `/notifications/` 000. Pass 2: `/` 000, jwks 200, `/statistics/` 000, `/tracking/` 401, `/notifications/` 401. Frontend body capture was empty. More `000` responses than on Linux; cause still open (port-forward race is a hypothesis, not established) |

Measured (single readings, app running): `podman stats` for the outer container 3.079 GB, 3.087 GB about 15 min later (Linux: 1.81 GB; difference not explained, `podman stats` memory may include page cache, not checked). `/var/lib/containers` 7.4 GB (same as Linux). Machine disk 8.8 GB used. The machine VM reported 15.8 GB total memory and 11.7 GB used at the end, but it already had 9.8 GB in use before the spike started, so that figure cannot be attributed to the spike. `podman machine list` showed 2 GiB for the machine while `free -m` inside it showed 15.8 GB; I did not establish why.

Repo copy into the container used `git archive HEAD`. Two repo defects surfaced and were fixed in commit `b91c638` (not re-run since): scripts were stored as mode 100644, and Windows `git archive` output had CRLF line endings, which broke the shebang line and `.env` sourcing. A root `.gitattributes` now forces LF for `*.sh`, `.env*`, `Dockerfile` and `*.conf`.

#### Task 1.1 follow-up: VS Code Dev Containers on Windows (VS Code 1.140.0, Dev Containers 0.469.0)

Tested with `dev.containers.dockerPath = "podman"` and a scratch folder containing a `devcontainer.json` that used the spike image.

- **Wayland socket mount fails.** The extension adds a bind mount of the WSLg socket as `\\wsl.localhost\Ubuntu\mnt\wslg\runtime-dir\wayland-0`; Podman rejects it ("unsupported UNC path"). Fixed with the user setting `dev.containers.mountWaylandSocket = false` (default `true`; found in the extension's `package.json`). It has application scope, so `devcontainer.json` cannot carry it; the host-setup guide must. Not checked: whether a host without WSLg hits the same error.
- **`runArgs: ["--entrypoint", ...]` does not work.** The extension appends its own `--entrypoint /bin/sh` after it, the last one wins, and the container exits before the extension can exec into it ("container state improper"). The earlier `overrideCommand: false` was dropped as well.
- **Working configuration:** `privileged`, `containerUser: root`, the storage volume mount and `"postStartCommand": "spike-init.sh /bin/true"` (the script's `exec "$@"` path, so it does the cgroup setup and exits). From the VS Code terminal: `0::/init`, `nested-ok`, `spike-minikube.sh` exit 0. So processes started by VS Code after `postStartCommand` land in `/init` and nested minikube works. Single run.
- The workspace bind mount from a Windows path (`c:\Users\...`) was accepted by Podman. The repo-in-volume workflow (D6) was not exercised.
- Version conflict from the earlier lookup: the VS Code page says Podman 5+, the README says >= 4. Tested here only with 6.0.2.

Not tested on Windows: compose health-check ordering (task 1.3), `deploy-minikube.sh` or compose from the VS Code container, a Hyper-V provider, a dedicated or freshly created machine, rootless mode, hosts without WSLg. macOS not tested.

Consequence for D2: the cgroup init step can run from `postStartCommand` instead of as PID 1, which the final `devcontainer.json` should use because the entrypoint override is not available through the extension.

### Compose providers in the real devcontainer, Windows, 2026-10-07 (task 1.3)

Host as above (Podman 6.0.2, rootful WSL machine). The real `.devcontainer/` (Fedora base, Podman 5.8.7 inside) was brought up with the CLI bundled in the Dev Containers extension (0.469.0), not through the VS Code UI. `postCreateCommand` left the host's existing `.env` and key unchanged and ran `npm ci`; `postStartCommand` printed `nested cgroup delegation enabled`, and the container shell was in `0::/init` without a manual step. Nested `podman run`, `docker` resolving to Podman, Java 21, Maven 3.9 and Node 20 behaved as expected. `podman-compose` 1.6.0 was installed by hand inside the running container (the image has only `docker-compose` 5.5.1). Test script: `spike-assets/spike-compose-test.sh`, unchanged, against the repo's unchanged `docker-compose.yml`. Single runs; build times mostly reflect the layer cache.

| Run | Options | Result |
|---|---|---|
| 1 | `podman-compose` | `up -d` timed out (exit 124). Podman executed the PostgreSQL health check 0 times, it never reported healthy, the other services stayed `Created`. `ordering=NEVER-HEALTHY` |
| 2 | `podman-compose`, health-check runner | `up -d` exit 0 in 10 s. Health check executed 5 times. The four dependent services started 351 to 1568 ms after PostgreSQL was first healthy. `ordering=PASS`. HTTP: `/`, 8081, 8082 returned 200; 8083 and 8084 returned `000` at probe time, 15 s after `up` (cause not established; JVM start-up is a guess) |
| 3 | `docker-compose` | Build and `up -d` exit 1 within 1 s: "failed to connect to the docker API at unix:///run/podman/podman.sock". Needs the Podman API socket |
| 4 | `docker-compose`, API socket | Build 739 s. `up -d` timed out; 0 health-check executions; `ordering=NEVER-HEALTHY` |
| 5 | `docker-compose`, API socket, health-check runner | `up -d` exit 0 in 8 s. Services started 469 to 1855 ms after PostgreSQL was healthy. `ordering=PASS`; all five HTTP probes 200 |

The health-check runner here is the script's own loop (`podman healthcheck run` on every running container every 5 s). It is a stand-in, not a design: whether a process started from `postStartCommand` survives VS Code reconnecting or a container restart was not tested.

Reading of the evidence: both providers honour `depends_on: service_healthy` once something executes the health checks, and neither does without it. `podman-compose` needs only the runner; `docker-compose` needs the runner and the API socket. The data do not decide the provider; the team has stated a preference for `podman-compose`, and that decision is not recorded here.

Defects found while running the kit:
- **`docker-compose-switch` recursion.** On Fedora 44, `dnf install docker-compose` also installs `docker-compose-switch` as a weak dependency, and `/usr/bin/docker-compose` is that shim, not Compose (the real binary is `/usr/libexec/docker/cli-plugins/docker-compose`). With `podman-docker` present the shim calls `docker compose`, which calls `podman compose`, which selects the shim again. The test script's `command -v docker-compose` picked the shim; run 3 then spawned processes until `fork: retry: Resource temporarily unavailable`, and the container had to be killed. Runs 3 to 5 were repeated with a symlink to the real binary first on `PATH`, with no change to the script or the image. If `docker-compose` is kept in the image it must be installed without weak dependencies (or the shim removed), and the kit's provider lookup needs the same care. Not checked: whether the default provider lookup of `podman compose` is affected by the shim when `docker-compose` is the only provider (it worked in part A of the run).
- `git` reports "detected dubious ownership" for the bind-mounted checkout (files appear owned by `podman`); `git rev-parse` fails until `safe.directory` is set. The test script falls back to `pwd`. Not yet handled in the devcontainer.

Not tested: Part D of the checklist (repository in a volume), a native Linux host, macOS, the VS Code UI path for this container, a restart of the container with the runner in place.

### Windows verification through the VS Code UI, 2026-10-07 (checklist 3)

Same Windows host as above. The real `.devcontainer/` was opened from the VS Code UI. Results come from the teammate's inline notes; steps that were ticked without a note are listed as "reported done, nothing captured" and are not evidence. Single runs.

| Part | What was recorded |
|---|---|
| A, setup | `vmware.vscode-boot-dev-pack` is "not necessary" and was removed from the extension list. The test script's own output (part B) shows `cgroup: 0::/init` and Podman 5.8.7, so `postStartCommand` ran its cgroup step through the UI path without a manual step. The other table checks were ticked without output. |
| B, compose + runner | `bash spike-compose-test.sh podman-compose` with **no** `--health` flag, so the real runner did the work: build 495 s; `up -d` exit 0 in 5 s; PostgreSQL healthy; the four dependents started 361, 608, 1089 and 1376 ms after it; `ordering=PASS`. HTTP: `8080` 200 after 1 s, `8081` after 14 s, `8082`, `8083`, `8084` 200 after 0 s. The earlier `000` on 8083 and 8084 was therefore start-up timing, not a fault. PostgreSQL's health log held 1 entry at inspection time. Confirmed afterwards by the teammate: `http://localhost:8080` loaded in the host browser, and registering, logging in and recording a drink worked. Not captured: whether VS Code forwarded the port by itself, `podman compose ps`. |
| C, Playwright | **2 passed, 17 failed in 33 s.** See the analysis below. |
| D1 | After "Reload Window" the runner kept the same pid. |
| D2 | Closing the window **stopped** the container. After reopening: runner running, cgroup `0::/init`, nested `podman run` works. |
| D3 | After `podman restart` on the host the VS Code connection is lost and the window must be reloaded. Confirmed afterwards by the teammate: after the reload the runner and `0::/init` were back, so a plain restart followed by a window reload restores the setup. |
| E | Confirmed afterwards by the teammate: `devcontainer-minikube-start` reached Ready and the unchanged `deploy-minikube.sh` exited 0 with six pods `1/1 Running`. Not recorded: start time, deploy duration, restart counts, the probe result. `minikube delete` was not ticked, so the cluster was up during the measurement. Memory with minikube and the application running: `podman stats` on the host **5.036 GB**; in the container `memory.stat` **anon 2,697,588,736 B (2.70 GB)**, **file 4,166,684,672 B (4.17 GB)**, shmem 71,319,552 B. |
| F | `terraform init -backend=false` with `validate`, and `deploy-azure.sh --help`, were ticked without output. Confirmed afterwards: `az login` was run and worked, and after a container rebuild `az account show` still worked without logging in again, so the `-azure` volume keeps the session. |
| G | Not run. |

**Playwright follow-up experiment (Windows, same day).** With fonts installed and `/dev/shm` remounted at 1 GB by hand, the e2e suite ran **18 passed, 1 skipped** (it had been 2 passed, 17 failed). So the crash hypothesis for the 15 login and dashboard failures held: the size of `/dev/shm` was the cause, and the register-page failures were the missing fonts. Not recorded: the result of the intermediate fonts-only run, which skipped test it was, the run time, and the peak `/dev/shm` use.

**Playwright analysis (part C).** Findings from the failure artefacts in the bind-mounted `e2e/test-results/`:
- *The two register-page failures are missing fonts.* The failure screenshot shows the register card with inputs, an error box and a button, but **no text**, while the page snapshot contains the text ("Create your account", "Registration failed. Please try again."). Reproduced in the built image: with no fonts installed a paragraph has a bounding box of height 0 and `isVisible()` is false, a button is 16×6 px; after installing `liberation-fonts` and `dejavu-sans-fonts` the same elements are visible (18 px; 104×21 px). `devcontainer-install-playwright` now installs both packages (tested through the script itself).
- *The 15 fixture and login failures are not explained by fonts.* The fixture registers by API, logs in through the UI, then expects `/dashboard`; it reports `page URL is http://localhost:8080/dashboard`, and the login test's log ends with "Target page, context or browser has been closed". The whole run took 33 s, far less than the sum of the 8 to 10 s waits, so these tests fail fast. Consistent with the browser page crashing after navigating to the dashboard. **Hypothesis, not reproduced:** the container's `/dev/shm` is 63 MB (checked), and Playwright's [Docker documentation](https://playwright.dev/docs/docker) says `--ipc=host` is recommended because without it "Chromium can run out of memory and crash". A one-command experiment (remount `/dev/shm` larger, rerun) would settle it; see tasks.
- The test "register with duplicate email shows error" only passes on a normal machine because its pattern also matches the page's "Already have an account?" paragraph; the application's own message is "Registration failed. Please try again.", which does not match. A weakness in the test, outside this change.

**Memory (parts E).** `memory.stat` separates anonymous memory (the resident working set) from file cache (reclaimable). With minikube and the application running on this host the working set is about 2.7 GB and the page cache about 4.2 GB, so the `podman stats` figure mixes both and is not a sizing requirement. The earlier Windows (3.08 GB) and Linux (1.81 GB) `podman stats` readings were taken at different times with different caches and cannot be compared; no Linux `anon` figure exists. Use the `anon` figure, labelled single and indicative.

**Extensions (task 3.2), Windows, 2026-10-07.** `code --list-extensions` inside the devcontainer lists the three IDs that had been marked unverified (`bradlc.vscode-tailwindcss`, `hashicorp.terraform`, `ms-playwright.playwright`) together with the Java pack parts, ESLint and the Kubernetes extension (plus `redhat.vscode-yaml`, presumably pulled in as a dependency; not checked). The Spring Boot pack was removed as unnecessary. No dedicated Helm extension was chosen.

### Go/no-go on nested minikube (task 1.6), decided 2026-10-07

**Decision: go.** minikube runs inside the devcontainer with the Podman driver (D3), and the README's minikube scenario stays as it is.

Basis:
- **Linux (WSL2 distro), rootful host Podman:** nested minikube and the unchanged `deploy-minikube.sh` worked (throwaway image, then the same flow again with variant B).
- **Windows (Podman Desktop, rootful WSL machine):** worked with the throwaway image, then with the real `.devcontainer/` opened from the VS Code UI: `devcontainer-minikube-start` reached Ready and `deploy-minikube.sh` exited 0 with six pods `1/1 Running`.
- It rests on three conditions that are now requirements: a **rootful** host engine, the cgroup delegation on **every** start (D2), and the documented start command with `--force` and no feature gate (D3).

Scope, so that "go" is not read as "verified everywhere":
- **Native Linux:** assumed to work through a rootful Podman machine; documented, never run (see the VERIFY in Open Questions).
- **macOS:** not tested; deferred.
- Both stay marked untested in the host-setup guide and do not block this change.
- A rootless host engine is out of scope: on the Linux host it needed an extra feature gate and pod networking still failed.

If a later test on native Linux or macOS fails, the fallback options are raised with the team and not decided here: a host-side minikube, or a different local Kubernetes tool. The one such option looked at, kind, would not remove the rootful and cgroup requirements and would mean rewriting `deploy-minikube.sh`, the ingress setup, `values-minikube.yaml`, the README scenario and the minikube specs (see the kind comparison from the exploration; Podman support in kind is documented as needing extra setup and its rootless guidance says nothing about rootful).

## Migration Plan

Additive. Developers who prefer a local setup keep the README flow. Rollback is deleting `.devcontainer/` and the guide. Rollout order: spike, then image and config, then guide, then a short README pointer.

## Deferred when this change was closed

Tasks 1.1 and 1.5 were closed with an explicit scope (2026-10-07), so these items are **not done** and belong to a follow-up:

- Run the devcontainer on a **native Linux** host (assumed to need a rootful Podman machine, qemu provider) and on **macOS**; replace the two `TODO` sections in `.devcontainer/README.md`. No Linux or macOS checklist exists yet; the Windows checklists in this folder are the template.
- Measure memory and disk for the compose stack alone on Windows, and a `anon` figure on Linux (no minimum is claimed anywhere).
- Test the "clone repository in container volume" flow with Podman, including the `dockerSocketPath` value.
- Record which e2e test skips itself and why, and the `/dev/shm` output, from the Windows recreate run.
- If a native Linux or macOS test fails, raise the fallback options with the team (see "Go/no-go on nested minikube").

## Open Questions

- Base image: `quay.io/podman/stable` works for nested Podman and minikube on Linux and Windows. Adopt it, or still evaluate a Debian-based image? The full toolchain on the Fedora base is untested.
- Decided: go on nested minikube (task 1.6). Still open: if a later test on native Linux or macOS fails, does the team accept a documented limitation, or switch tooling?
- Required memory and disk per host (to be measured).
- > **VERIFY:** Linux native hosts are **assumed** to work through a rootful Podman machine (qemu provider, documented, never run). The host-setup guide and the Linux parts of the verification tasks must stay marked untested until a native Linux developer has run the Linux checklist. If it fails, the fallback paths are a rootful socket or a `sudo` wrapper, which are root-equivalent for the developer.
- > **VERIFY:** health-check runner (D11): verified through the VS Code UI on Windows (ordering passes with no helper flag; same pid after a window reload; running again after close and reopen). After a plain `podman restart` VS Code loses the connection; reloading the window restores the runner and `0::/init` (confirmed by the teammate). Not verified: native Linux or macOS.
- > **VERIFY:** the user reported that everything works after recreating the container with `--shm-size=1g` and the fonts fix (task 4.9); the `/dev/shm` output, the skipped test (history date-filter inputs not found, or no notification warning within 6 minutes) and the run time were not captured.
- > **OPEN QUESTION:** does the "clone repository in container volume" flow (D6) work with Podman? It appears to use `dev.containers.dockerSocketPath`; not tested.
- Dev Containers launch with Podman: verified on Windows only. Does it work from VS Code on Linux (rootful) and macOS, and are other editors in use?
