# devcontainer-environment Specification

## Purpose
Specifies the Podman-based development container of Beer Tracker: the toolchain it provides, how it runs nested containers and minikube on a rootful host engine, how secrets are handled, what the host must provide, and how its risky assumptions were validated. Design, measurements and the Windows verification are in the archived change `2026-10-07-add-podman-devcontainer`; the user-facing guide is `.devcontainer/README.md`.
## Requirements
### Requirement: Devcontainer provides the development and test toolchain
The devcontainer SHALL provide JDK 21, Maven 3.9, Node 20 with npm, openssl, git and a PostgreSQL client, so that the four Spring Boot services and the frontend can be built and the e2e project installed without any host-installed tooling.

#### Scenario: Backend builds inside the container
- **WHEN** a developer runs `mvn package` in any `services/*` directory inside the devcontainer
- **THEN** the build uses JDK 21 and completes without requiring tools from the host

#### Scenario: Frontend builds inside the container
- **WHEN** a developer runs `npm ci` and `npm run build` in `frontend/`
- **THEN** the build completes using Node 20

### Requirement: Devcontainer provides the deployment toolchain at the documented minimum versions
The devcontainer SHALL provide Podman >= 4, kubectl, helm >= 3.10, minikube >= 1.32, terraform >= 1.9 and the Azure CLI >= 2.60, matching the prerequisites stated in the README.

#### Scenario: Tool versions meet the minimums
- **WHEN** a developer queries the version of each deployment tool inside the container
- **THEN** each reports a version at or above its documented minimum

### Requirement: Podman is the container engine and `docker` resolves to it
The devcontainer SHALL use Podman as its only container engine, run privileged so Podman operates inside it, and SHALL make the `docker` command resolve to Podman in non-interactive shells so that `scripts/deploy-azure.sh` runs unchanged.

#### Scenario: Docker command is Podman
- **WHEN** a non-interactive script runs `docker --version`
- **THEN** the output identifies Podman

#### Scenario: Short image names resolve
- **WHEN** the compose stack pulls `postgres:16-alpine` and `nginx:alpine`
- **THEN** the images are pulled from docker.io without interactive prompts or modification of `docker-compose.yml`

### Requirement: Nested containers can create cgroups on every container start
The devcontainer SHALL, on every start (not only on creation), arrange that the container's own cgroup can delegate controllers to nested cgroups, so that nested Podman and minikube can create resource-limited containers, and SHALL keep nested workloads accounted to the devcontainer's own cgroup. The arrangement SHALL be safe to run repeatedly and SHALL NOT depend on replacing the container's entrypoint.

#### Scenario: Nested containers start after the first start
- **WHEN** the devcontainer has started and a developer runs `podman run --rm docker.io/library/alpine:3.20 echo nested-ok` in a terminal opened through the IDE
- **THEN** the output is `nested-ok`

#### Scenario: Repeated starts
- **WHEN** the container is stopped and started again
- **THEN** nested containers can again be created without manual steps

#### Scenario: Shell processes are in the delegated sub-cgroup
- **WHEN** a developer runs `cat /proc/self/cgroup` in an IDE terminal
- **THEN** the path is a sub-cgroup (for example `/init`) and not the container's top-level cgroup

### Requirement: The local compose stack runs inside the container
The devcontainer SHALL run the existing `docker-compose.yml` stack through one pinned compose provider that honours `depends_on` with `condition: service_healthy`.

#### Scenario: Stack starts and serves the frontend
- **WHEN** a developer runs `podman compose up -d` and waits for services to become healthy
- **THEN** `curl http://localhost:8080` returns the frontend HTML

#### Scenario: Services wait for PostgreSQL health
- **WHEN** the stack starts from a fresh volume
- **THEN** dependent services start only after the `postgres` health check passes

#### Scenario: No manual service start is needed
- **WHEN** a developer opens a new terminal in the devcontainer and runs the compose command
- **THEN** it works without first starting any helper process (for example an API socket service or a health-check runner) by hand

### Requirement: minikube runs inside the container with the Podman driver
The devcontainer SHALL support running minikube with the Podman driver and the existing `scripts/deploy-minikube.sh` flow without changes to the script, charts or values files. Because minikube runs as root inside the container and the README's plain `minikube start` is not sufficient there, the devcontainer SHALL provide and document one start command that works without extra feature gates on a rootful host engine.

#### Scenario: Minikube starts with the documented command
- **WHEN** a developer runs the documented minikube start command in the devcontainer
- **THEN** the cluster node reaches `Ready`

#### Scenario: Minikube deployment succeeds
- **WHEN** a developer starts minikube with the documented command and runs `./scripts/deploy-minikube.sh`
- **THEN** images are built with `minikube image build` and all pods in the `beer-tracker` namespace reach `Running`

### Requirement: Playwright e2e tests can run against the local stack
The devcontainer SHALL allow the Playwright suite in `e2e/` to run against the compose stack, with browser installation available as an opt-in step that is not part of the base image.

#### Scenario: Opt-in browser install then e2e run
- **WHEN** a developer runs `devcontainer-install-playwright` from the repository root and then `npm run test:e2e` in `e2e/` with the stack running
- **THEN** the tests execute against `http://localhost:8080`

#### Scenario: Shared memory is large enough for headless Chromium
- **WHEN** a developer runs `df -h /dev/shm` in the devcontainer
- **THEN** the size is at least 1 GB, and the e2e suite does not fail with "Target page, context or browser has been closed"

#### Scenario: Browser is not in the base image
- **WHEN** the image is inspected
- **THEN** it contains no Playwright browser download

### Requirement: Secrets are generated, never copied or baked in
The devcontainer SHALL generate the RSA private key at `secrets/auth-rs256-private-key.pem` and create `.env` from `.env.example` on first creation only when they do not already exist, and SHALL NOT bake secrets, `.env` files or Terraform state into the image, copy them from elsewhere on the host, or add any host mount other than the workspace and named volumes. The developer's own gitignored files that already exist in the checked-out workspace (for example `.env`, the RSA key or Terraform state in a bind-mounted checkout) are the developer's own and SHALL be used unchanged; the host-setup guide SHALL state that a bind-mounted checkout makes them visible to every process in the privileged container.

#### Scenario: First creation
- **WHEN** the devcontainer is created in a checkout without `.env` or the key file
- **THEN** both are created, and the compose stack can start using them

#### Scenario: Existing files are preserved
- **WHEN** the devcontainer is created or rebuilt and `.env` and the key already exist in the workspace
- **THEN** neither file is overwritten

#### Scenario: Image contains no secrets
- **WHEN** the image layers and `devcontainer.json` are inspected
- **THEN** they contain no key material, passwords or credentials

#### Scenario: No host mounts beyond the workspace
- **WHEN** `devcontainer.json` is inspected
- **THEN** its mounts are named volumes only, and the build context contains no `.env`, key or state files

#### Scenario: Repository cloned into a volume
- **WHEN** the devcontainer is opened through "clone repository in container volume"
- **THEN** no host secrets are present, and `.env` and the key are generated by the first creation

### Requirement: Azure access uses an interactive login with persisted state
The devcontainer SHALL support `az login` using the device code flow and SHALL persist Azure CLI state and kubeconfig in named volumes, without embedding credentials.

#### Scenario: Login survives a rebuild
- **WHEN** a developer logs in, rebuilds the container, and runs `az account show`
- **THEN** the session is still available from the named volume until it expires

### Requirement: Caches and working copy avoid slow host mounts
The devcontainer SHALL use named volumes for nested Podman's container storage, the Maven cache, `node_modules`, Azure CLI state, kubeconfig and minikube data, and SHALL document cloning the repository into the container volume rather than bind-mounting it from the host.

#### Scenario: Cache survives rebuild
- **WHEN** the container is rebuilt
- **THEN** previously downloaded Maven dependencies and `node_modules` remain available

### Requirement: Application ports are forwarded
The devcontainer SHALL forward ports 8080, 8081, 8082, 8083, 8084 and 5173 to the developer's host.

#### Scenario: Browser access
- **WHEN** the compose stack is running
- **THEN** the application is reachable at `http://localhost:8080` from the host browser

### Requirement: One configuration serves all host operating systems
The devcontainer SHALL use a single `devcontainer.json` that works on Windows, macOS and Linux hosts running Podman, and SHALL ship a host-setup guide stating per-OS prerequisites, including that on Windows a Podman machine (backed by WSL2 or Hyper-V) is required. The guide SHALL state that the host engine must run rootful, how to verify that, the IDE settings required to launch the devcontainer with Podman, and a tested combination of IDE, Dev Containers extension and Podman versions. Statements about a host OS that has not been tested SHALL be marked as untested in the guide.

#### Scenario: Host guide covers each OS
- **WHEN** a developer opens the host-setup guide
- **THEN** it lists the prerequisites and any launch settings for Windows, macOS and Linux

#### Scenario: Rootful check
- **WHEN** a developer follows the guide's verification step on the host
- **THEN** `podman info --format "{{.Host.Security.Rootless}}"` prints `false` before the devcontainer is opened

#### Scenario: Required IDE settings are listed
- **WHEN** a developer on Windows with WSLg opens the guide
- **THEN** it lists `dev.containers.dockerPath` set to `podman` and `dev.containers.mountWaylandSocket` set to `false`, and states that the latter is a user setting that `devcontainer.json` cannot carry

### Requirement: Risky assumptions are validated by a spike before the image is finalised
The change SHALL include a spike that, on each of Windows, macOS and Linux hosts, verifies nested minikube with the Podman driver, compose health-check ordering, and measures memory and disk use, and SHALL record the results; figures SHALL NOT be stated in documentation before they are measured.

#### Scenario: Spike results are recorded
- **WHEN** the spike tasks are complete
- **THEN** the results per host type, including measured memory and disk, are written to the change's design or the host-setup guide

