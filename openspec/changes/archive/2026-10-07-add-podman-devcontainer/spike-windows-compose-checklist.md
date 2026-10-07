# Windows checklist 2 — compose providers (task 1.3) in the real devcontainer

Part of the OpenSpec change `add-podman-devcontainer`. Checklist 1 (`spike-windows-checklist.md`) tested nested
minikube with a throwaway image. This one runs in the **real** `.devcontainer/` and answers one question:

> Which compose provider, `podman-compose` or `docker-compose`, makes the repo's unchanged `docker-compose.yml`
> start with **PostgreSQL first**, and what extra setup does it need without systemd inside the container?

Background: `podman compose` is a thin wrapper that runs an external *provider*. If both are installed,
`docker-compose` wins by default, so the script below selects the provider explicitly with
`PODMAN_COMPOSE_PROVIDER` (per the [Podman reference](https://docs.podman.io/en/latest/markdown/podman-compose.1.html)).
**The team prefers `podman-compose`**, so it is tested first; `docker-compose` is the comparison and the fallback.

**Status of these instructions:** the test script was checked only against a mock of `podman`. It has not been run
against real Podman, and the `podman inspect` template forms it uses are unverified. If a number or message looks
wrong, trust what you see in the terminal, and note the discrepancy in the results sheet.

## 0. Before you start

- [ ] A branch that contains `.devcontainer/` **and** `openspec/changes/add-podman-devcontainer/spike-assets/spike-compose-test.sh`.
      > **TODO(Michael):** commit and push such a branch; at the time of writing both are uncommitted.
- [ ] The VS Code user settings from checklist 1 are still in place: `dev.containers.dockerPath` = `podman` and
      `dev.containers.mountWaylandSocket` = `false`.
- [ ] Your Podman machine is rootful: `podman info --format "{{.Host.Security.Rootless}}"` prints `false`.
- [ ] Time and space: the first run builds five images inside the container (about 13 minutes on the Linux host,
      mostly Maven downloads; yours depends on bandwidth). On Linux the nested container storage was about 4 GB after one
      compose stack. These are single observations, not requirements.
- [ ] Note your versions: Windows build, Podman, VS Code, Dev Containers extension.

## A. Open the real devcontainer

- [ ] Open the repository folder in VS Code and run "Dev Containers: Reopen in Container".
      Record: did the build succeed (about 3 minutes on Linux, 2.2 GB image)? Any extension that failed to install? (four extension
      IDs in `devcontainer.json` are marked `VERIFY`.)
- [ ] In a VS Code terminal inside the container, check each item and record the output:
      - `cat /proc/self/cgroup` — **expect `0::/init`.** That proves `postStartCommand` ran the cgroup setup without any manual step.
        If it prints `0::/`, run `devcontainer-cgroup-init`, open a new terminal, and record that the automatic step did not work.
      - `podman run --rm docker.io/library/alpine:3.20 echo nested-ok` — expect `nested-ok`
      - `docker --version` — expect `podman version ...`
      - `ls -la .env secrets/` — expect `.env` and `secrets/auth-rs256-private-key.pem` created by the post-create step
      - `java -version; mvn -v; node -v` — expect Java 21, Maven 3.9, Node 20
- [ ] Is the workspace a bind mount from a Windows path? (Yes if you opened a local folder.) Record the path style.

## B. Install the second provider (for this test only; do not change the image)

- [ ] `dnf -y install podman-compose`
- [ ] Record both versions: `podman-compose --version` and `docker-compose version`

## C. The runs

Run from the repository root in the VS Code terminal. Each run removes the compose project `spike` before and after,
so runs do not affect each other. The script path is
`openspec/changes/add-podman-devcontainer/spike-assets/spike-compose-test.sh`; call it `$T` below:

```bash
T=openspec/changes/add-podman-devcontainer/spike-assets/spike-compose-test.sh
```

| # | Command | What it tests | Expected from the Linux spike (provider `docker-compose` only; the other is unknown) |
|---|---|---|---|
| 1 | `bash $T podman-compose` | `podman-compose` with nothing extra | unknown |
| 2 | `bash $T podman-compose --health` | `podman-compose` plus a background health-check runner | unknown |
| 3 | `bash $T docker-compose` | `docker-compose` with nothing extra | fails: needs the Podman API socket |
| 4 | `bash $T docker-compose --socket` | adds the API socket | hangs: health check never runs |
| 5 | `bash $T docker-compose --socket --health` | adds the health-check runner | worked (under a different container config) |

- [ ] Run 1, then 2, then 3, 4, 5. If run 1 or 2 already gives a clean result, still do 3 to 5; they are the baseline for the decision.
      The first run is slow because it builds the images; later runs reuse cached layers.
- [ ] Each run ends with a line starting `RESULT`. Copy that line, and the lines above it (container states, health-check count,
      per-service ordering, HTTP codes), into the results sheet. All output is also appended to `/tmp/spike-compose-results.log`.
- [ ] If a run hangs for more than the build or up timeout, the script stops it by itself (`up -d` after 180 s, build after 30 min).

How to read a result:

| You see | It means |
|---|---|
| `ordering=PASS`, HTTP all `200` | the provider started the services after PostgreSQL reported healthy |
| `ordering=NEVER-HEALTHY`, "executed by Podman: 0 time(s)" | Podman never ran the PostgreSQL health check, so nothing can wait for it. The runner (`--health`) is needed. |
| `ordering=SUSPECT-RESTARTS` | services crash-looped and `restart: unless-stopped` eventually made it work. Works by retry, not by ordering. |
| `ordering=FAIL` with "BEFORE postgres healthy" | the provider ignores `service_healthy` |
| `up -d: exit=124` | the provider waited past the timeout (typically waiting on a health status that never changes) |
| build fails with an error about the Docker API / socket | `docker-compose` needs `podman system service` running (`--socket`) |

## D. Optional: repository in a volume (design decision D6)

Only if you have time. This tests the "clone repository in container volume" flow, which the extension appears to run through
`dev.containers.dockerSocketPath` (default `/var/run/docker.sock`).

- [ ] Command Palette: "Dev Containers: Clone Repository in Container Volume...", repository URL and the same branch.
- [ ] Record whether it works as is. If it fails, record the exact error, then set `dev.containers.dockerSocketPath` to
      `/run/podman/podman.sock` and retry; record which value worked, if any.
      > **VERIFY:** that path is my guess for a rootful Podman machine, not something I have confirmed.

## E. Clean up

- [ ] The script removes the compose project itself. To free space afterwards, close the devcontainer and delete its volumes
      (`podman volume ls` on the host; they are named after the devcontainer id and end in `-containers`, `-m2`, `-azure`, `-kube`,
      `-minikube`, `-frontend-node-modules`, `-e2e-node-modules`). Keep them if you will run more tests.

## Results sheet — send this back

| Item | Result |
|---|---|
| Windows build, Podman, VS Code, Dev Containers extension versions | |
| Devcontainer opened? build time, failed extensions | |
| `/proc/self/cgroup` (expect `0::/init`) | |
| `podman-compose` and `docker-compose` versions | |
| Run 1 `RESULT` line + notes | |
| Run 2 `RESULT` line + notes | |
| Run 3 `RESULT` line + notes | |
| Run 4 `RESULT` line + notes | |
| Run 5 `RESULT` line + notes | |
| Health checks executed by Podman without the runner (runs 1, 3, 4) | |
| Did any run need a manual step (starting a service, a command) beyond the script flags? | |
| Part D result, if run | |
| Commands you had to change; anything unexpected, with exact error text | |

> **OPEN QUESTION:** the spec requires that no manual helper process is needed to run compose. If only `--health` runs pass, the image
> needs a background process started from `postStartCommand` (design D11), and nobody has yet checked that such a process survives
> VS Code reconnecting or the container restarting. Note any sign of it dying in "anything unexpected".
