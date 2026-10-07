## Why

Developing, testing and deploying Beer Tracker needs JDK 21, Maven, Node 20, a container engine, kubectl, helm, minikube, terraform and the Azure CLI, each at a minimum version stated only in the README. Every team member installs and aligns these by hand, on Windows, macOS and Linux hosts. A devcontainer makes the toolchain reproducible and lets a new developer reach a working stack with one step. The team standardises on Podman, so the environment must be Podman-based rather than Docker-based.

## What Changes

- Add a `.devcontainer/` (Dockerfile, `devcontainer.json`, lifecycle scripts) that provides the full manual dev/test/deploy toolchain, with no AI-agent tooling.
- Toolchain in the image: JDK 21, Maven 3.9, Node 20, Podman (with `podman-docker` so the literal `docker` calls in `scripts/deploy-azure.sh` resolve to Podman), one pinned compose provider, kubectl, helm >= 3.10, minikube >= 1.32, terraform >= 1.9, Azure CLI >= 2.60, openssl, git and a PostgreSQL client.
- The devcontainer runs privileged so Podman can run (rootful) inside it, and minikube runs inside the container with `--driver=podman`.
- A single `devcontainer.json` serves Windows, macOS and Linux hosts. Host differences are documented, not forked into per-OS configs.
- Named volumes for Maven cache, `node_modules`, Azure CLI state, kubeconfig and minikube data; the repository is intended to live in the container volume, not a host bind mount.
- Lifecycle step generates the RSA key and `.env` from `.env.example` (never copies existing secrets), and installs frontend dependencies. Playwright browsers are opt-in.
- Port forwarding for 8080, 8081-8084 and 5173.
- Add a host-setup guide: Podman prerequisites per host OS (on Windows, Podman machine, which needs WSL2 or Hyper-V underneath).
- Start with a spike that proves the risky parts on all three host types before the image is finalised.

Not changed: application code, Helm charts, Terraform, `docker-compose.yml`, and the deploy scripts. No **BREAKING** changes.

## Capabilities

### New Capabilities
- `devcontainer-environment`: the devcontainer image and configuration, toolchain and versions, privileged Podman runtime, volumes, port forwarding, lifecycle (key/`.env` generation, dependency install), secret-handling rules, and the host-prerequisites documentation.

### Modified Capabilities
<!-- None. Existing specs (local-compose-deployment, local-minikube-deployment, e2e-testing, azure-aks-deployment) keep their requirements; the devcontainer must satisfy them, not change them. -->

## Impact

- New files: `.devcontainer/` and a host-setup document. README gets a pointer only.
- Affects every developer's local setup; no runtime or production impact.
- Depends on host Podman and, on Windows, a working Podman machine with virtualisation enabled (may need admin rights).
- Open risks, to be settled by the spike rather than assumed: minikube's podman driver nested in a privileged container; whether the chosen compose provider honours `depends_on: condition: service_healthy`; memory and disk required for the stack plus minikube (not yet measured). If minikube-in-Podman proves unworkable, the fallback (for example kind or k3d) would change `scripts/deploy-minikube.sh`, `values-minikube.yaml` and the README, and is a team decision outside this change.
- Observed, out of scope: the README minikube troubleshooting row still recommends `eval $(minikube docker-env)`, which contradicts the comment in `scripts/deploy-minikube.sh`.
