## Context

The Dockerfile installs each deployment tool from a pinned release artefact and verifies a checksum fetched from the same origin (kubectl, minikube, helm, terraform). The Azure CLI is installed from Microsoft's RPM repository at a pinned version. The AKS cluster has local accounts disabled and Entra ID RBAC enabled, so `kubectl` needs the `kubelogin` exec plugin, which the image lacks.

Findings from exploration (2026-10-08, Azure CLI 2.91.0, the version pinned in the Dockerfile):

- `az aks install-cli` is documented ([Azure CLI reference](https://learn.microsoft.com/en-us/cli/azure/aks?view=azure-cli-latest#az-aks-install-cli); [kubelogin install guide](https://azure.github.io/kubelogin/install.html)). It installs both `kubectl` and `kubelogin` and accepts `--client-version`, `--install-location`, `--kubelogin-version` and `--kubelogin-install-location`.
- It does not require `az login`: run with an empty `AZURE_CONFIG_DIR`, it still downloaded both binaries (kubectl from `dl.k8s.io`, kubelogin from `github.com`). Single run.
- Without `--kubelogin-version` it queries the GitHub API for the latest release; that request hit a rate limit (HTTP 403) and the command fell back to a version file on `github.com`.
- No checksum verification is visible in its output.

## Goals / Non-Goals

**Goals:**
- `kubelogin` is on the `PATH` of the built image at a pinned, reproducible version.
- The pinned `kubectl` v1.34.1 (checksum-verified) is unchanged.

**Non-Goals:**
- Choosing or testing the kubelogin login mode (device code vs. Azure CLI token via `kubelogin convert-kubeconfig`).
- Running the full AKS deploy from the container.
- Changing the deploy scripts or Terraform.

## Decisions

**D1: Install with `az aks install-cli`, not a direct release download.**
Requested approach; it is documented, needs no extra tooling (`az` is already in the image) and supports version pinning. Alternative: download the release zip from GitHub and verify a checksum, which matches the other tools. Rejected for now because the project owner chose the documented command; the cost is the missing checksum (see Risks).

**D2: Pin with a new `ARG KUBELOGIN_VERSION` and always pass `--kubelogin-version`.**
Matches the Dockerfile's convention of pinned ARGs and avoids the unauthenticated GitHub API lookup that was rate limited. The exact version is chosen at implementation from the upstream releases page (v0.2.20 is the latest release per `kubelogin-version.txt` on 2026-10-08; pinned).

**D3: Keep the pinned kubectl; send the command's kubectl download to a throwaway path.**
The command has no documented "kubelogin only" option, so it always downloads a kubectl. Pointing `--install-location` at `/usr/local/bin/kubectl` would replace the checksum-verified binary. Instead pass `--client-version ${KUBECTL_VERSION}` and `--install-location /tmp/kubectl-unused/kubectl` (the command rejects an install path whose file name is not `kubectl`; a first attempt with `/tmp/kubectl-unused` errored for the kubectl step while still installing kubelogin), and delete that directory in the same `RUN`. Alternative: run it before the kubectl step so the verified binary overwrites it; rejected because it relies on ordering and still leaves an unverified intermediate. Cost: one wasted kubectl download at build time.

**D4: Set `--kubelogin-install-location /usr/local/bin/kubelogin`.**
Same directory as the other tools, which is on the `PATH`.

## Risks / Trade-offs

- [No checksum on the kubelogin binary] → Pinned version limits drift, but a compromised release or download would not be detected. The Dockerfile already notes that its own checksums only catch corruption, not a compromised server. Mitigation option: switch to the release download with a checksum (D1 alternative) if this matters. Recorded as an open question.
- [`az aks install-cli` behaviour changes in a newer Azure CLI] → Azure CLI is pinned (`AZURE_CLI_VERSION`); re-check on bumps.
- [Build-time dependency on `github.com`] → The image build already depends on GitHub for the JDK and minikube.
- [AKS path through kubelogin untested] → Documented as `VERIFY` in `.devcontainer/README.md`.

## Open Questions

- Which release to pin for `KUBELOGIN_VERSION`.
- Is the missing checksum acceptable, or should a checksum-verified download replace `az aks install-cli`?
- Which kubelogin login mode should the container use (device code vs. `azurecli`)? Untested; out of scope here.
- Does `az aks get-credentials` in 2.91.0 write a kubeconfig that calls `kubelogin` by default? Not checked.
