# Windows spike checklist — Podman devcontainer for fhlva-aidlc-app

Part of the OpenSpec change `add-podman-devcontainer` (task group 1, the spike). Background and
the Linux results are in `design.md`, section "Spike Findings". This checklist repeats the Linux
spike on a Windows host. **You are checking whether the setup works; you are not expected to fix it.**
If a step fails, copy the exact error text into the results sheet at the end and move on to the next
independent part.

**Status of these instructions:** the Dockerfile and helper scripts were built and partly tested on
Linux. Every PowerShell command below is untested on Windows. If a command needs changing, change it
and note the difference in the results sheet.

## 0. Before you start

- [ ] You have a Windows 11 x86-64 machine with hardware virtualisation enabled in firmware. (Podman's Windows
      tutorial requires Windows 11 or later; Hyper-V is not available on Windows Home.)
- [ ] You can free about 20 GB of disk and about 8 GB of RAM for the spike. These are working
      assumptions, not measured requirements; the point of Part E is to measure them.
- [ ] You know whether you may use administrator rights. WSL needs none in the usual case; the first
      Hyper-V machine needs them.
- [ ] You have a checkout of this repository on a branch that contains **both** the `openspec/changes/add-podman-devcontainer/`
      folder (including `spike-assets/`) **and** the fixed `scripts/deploy-minikube.sh` (single
      `beer-tracker-secrets` Secret). Without the script fix the app pods cannot start.
      > **TODO(Michael):** commit and push such a branch; at the time of writing the fix and the spike
      > assets are uncommitted in Michael's working tree.
- [ ] Git for Windows does not rewrite shell scripts to CRLF (`spike-assets/.gitattributes` forces LF; check with
      `git ls-files --eol openspec/changes/add-podman-devcontainer/spike-assets` that `*.sh` show `w/lf`).
- [ ] You use a **dedicated** Podman machine called `spike-win` and leave any existing machine alone.
      Switching a machine to rootful hides its existing images and containers from the default connection.

Variables used below (PowerShell):

```powershell
$REPO = "C:\path\to\fhlva-aidlc-app"        # your checkout
$ASSETS = "$REPO\openspec\changes\add-podman-devcontainer\spike-assets"
```

## A. Record the environment

- [ ] Windows edition and build: `winver` (or `Get-ComputerInfo | Select WindowsProductName, OsVersion`)
- [ ] Total RAM and CPU count: `Get-ComputerInfo | Select CsTotalPhysicalMemory, CsNumberOfLogicalProcessors`
- [ ] Podman version: `podman --version` (VS Code's documentation says Podman 5+; the repo README says 4+)
- [ ] VS Code and Dev Containers extension versions (only needed for Part F)
- [ ] Existing machines and connections, so you can restore them: `podman machine list` and `podman system connection list`.
      Note which connection is the default.

## B. Create a rootful Podman machine

Provider: use `wsl` unless your machine only supports Hyper-V. Record which one you used.

- [ ] `podman machine init spike-win` (add `--provider wsl` or `--provider hyperv` if needed; for Hyper-V the first init needs an
      administrator shell and your user must be in the Hyper-V Administrators group)
- [ ] `podman machine set --rootful spike-win` (the machine must not be running; the Podman tutorial says to stop it first)
- [ ] `podman machine start spike-win`
- [ ] Make sure the default connection points at this machine (`podman system connection list`; set with
      `podman system connection default <name>` if not).
- [ ] **Expect `false`:** `podman info --format "{{.Host.Security.Rootless}}"`
- [ ] **Expect `cgroup2fs`:** `podman machine ssh spike-win "stat -fc %T /sys/fs/cgroup"`
      - If it prints `tmpfs` (cgroup v1) the container's cgroup fix cannot work. Record it. For the WSL provider a community
        discussion reports adding `kernelCommandLine = cgroup_no_v1=all` under `[wsl2]` in `%UserProfile%\.wslconfig`, then
        `wsl --shutdown` and restarting the machine. That setting affects **all** your WSL distributions, so only try it if you accept that,
        and record that you did.
- [ ] Record the memory the machine can use: `podman machine ssh spike-win "free -m"`

## C. Build the candidate image and start the container

- [ ] Build (about 30 s on the Linux host; depends on bandwidth): `podman build -t spike-devc-win "$ASSETS"`
- [ ] `podman volume create spike-win-storage`
- [ ] Start it (the container runs `spike-init.sh` as its first process, which prepares cgroups and then idles):
      `podman run -d --name spike-win --privileged --user root -v spike-win-storage:/var/lib/containers localhost/spike-devc-win:latest spike-init.sh`
- [ ] **Expect `0::/init`:** `podman exec spike-win cat /proc/self/cgroup`
- [ ] **Expect `nested-ok`:** `podman exec spike-win podman run --rm docker.io/library/alpine:3.20 echo nested-ok`
- [ ] **Expect "Podman" in the output:** `podman exec spike-win docker --version`

## D. minikube and the application

- [ ] Copy the repository into the container (committed files only, so no secrets travel):
      ```powershell
      git -C $REPO archive --format=tar -o "$env:TEMP\repo.tar" HEAD
      podman cp "$env:TEMP\repo.tar" spike-win:/tmp/repo.tar
      podman exec spike-win bash -c "rm -rf /work && mkdir -p /work && tar -xf /tmp/repo.tar -C /work"
      ```
- [ ] Create throwaway secrets inside the container: `podman exec spike-win spike-prepare.sh`
      (expect `required variables set: 3/3; key present: yes`)
- [ ] Start minikube with the plain command (Linux: exit 0 in about 24 s): `podman exec spike-win spike-minikube.sh`
      Record `minikube exit=`, the `real` time and the last line (`node/spike condition met`).
      On failure copy the printed lines; the full log is `/tmp/mk.log` in the container
      (`podman cp spike-win:/tmp/mk.log .\mk.log`).
- [ ] Deploy with the repo's unchanged script (Linux: exit 0 after 427 s, including five image builds; yours depends on bandwidth):
      `podman exec spike-win spike-deploy.sh`
      Record the exit code, the seconds, and the pod list. **Expect** six pods `1/1 Running` with `restarts=0`.
      If not, keep the "not ready" lines it prints.
- [ ] Probe through the ingress: `podman exec spike-win spike-probe.sh`
      **Expect** `port-forward answering: yes`; `/` returns 200 and `/auth/.well-known/jwks.json` returns 200;
      `/statistics/`, `/tracking/` and `/notifications/` are authenticated endpoints, so 401 or 403 is plausible.
      On the Linux run `/notifications/` and the first `/` request returned `000` (no HTTP response) and the cause is open.
      Record both passes, and whether any `000` appears.

## E. Measurements (single readings; say when each was taken)

- [ ] Container memory with the full app running: `podman stats --no-stream spike-win`
- [ ] Same reading again after 60 seconds.
- [ ] Container storage: `podman exec spike-win du -sh /var/lib/containers`
- [ ] Machine memory and disk: `podman machine ssh spike-win "free -m; df -h /"`
- [ ] Windows host memory in use while the app runs (Task Manager is fine). Record that it is approximate.

Linux reference points (one host, indicative only): outer container about 1.8 GB with the full app; about 7.4 GB in `/var/lib/containers`.

## F. Optional: open it from VS Code

This checks the part of task 1.1 that documentation cannot answer. Stop the Part C container first
(`podman stop spike-win`) so the two do not compete for memory.

- [ ] In VS Code user settings set `"dev.containers.dockerPath": "podman"`.
- [ ] Create `.devcontainer/devcontainer.json` in an empty scratch folder:
      ```json
      {
        "name": "spike-win",
        "image": "localhost/spike-devc-win:latest",
        "privileged": true,
        "containerUser": "root",
        "overrideCommand": false,
        "runArgs": ["--entrypoint", "/usr/local/bin/spike-init.sh"],
        "mounts": ["source=spike-vsc-storage,target=/var/lib/containers,type=volume"]
      }
      ```
      > **VERIFY:** these properties are my reading of the devcontainer spec and have not been run. Adjust if VS Code rejects them and record what you changed.
- [ ] "Dev Containers: Reopen in Container". Record success or the exact error, plus the VS Code, extension and Podman versions.
- [ ] In the VS Code terminal inside the container: `cat /proc/self/cgroup` (is the shell in `/init`, or elsewhere?),
      then `podman run --rm docker.io/library/alpine:3.20 echo nested-ok`, then `spike-minikube.sh`.
      The open question is whether processes started by VS Code still allow the cgroup fix to work.

## G. Clean up

- [ ] `podman rm -f spike-win` (and the Part F container if you ran it)
- [ ] `podman volume rm spike-win-storage spike-vsc-storage`
- [ ] `podman rmi localhost/spike-devc-win`
- [ ] `podman machine stop spike-win` and `podman machine rm spike-win` (check the name first; this deletes the machine)
- [ ] Restore your previous default connection: `podman system connection default <name you noted in Part A>`
- [ ] Remove `$env:TEMP\repo.tar` and the scratch folder from Part F.

## Results sheet — send this back

| Item | Result |
|---|---|
| Windows edition / build | |
| Podman version, provider (wsl / hyperv) | |
| Rootless value (expect false) | |
| cgroup type in the machine (expect cgroup2fs); `.wslconfig` change needed? | |
| Machine memory | |
| Image build OK? | |
| `/proc/self/cgroup` in container (expect `0::/init`) | |
| Nested `podman run` OK? `docker` is Podman? | |
| minikube exit code and time | |
| deploy script exit code and seconds | |
| Pods (name, ready, restarts) | |
| Probe results, both passes, any `000` | |
| Container memory (now, +60 s), container storage, machine disk | |
| Part F: VS Code opens the container? versions? terminal cgroup? minikube from VS Code? | |
| Commands you had to change | |
| Anything unexpected, with exact error text | |

> **OPEN QUESTION:** if Part B shows cgroup v1 and the `.wslconfig` change is needed, the host-setup guide would have to ask every
> Windows developer to change a setting that affects all of their WSL distributions. The team should decide whether that is acceptable.
