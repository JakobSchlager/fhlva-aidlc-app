## Why

The AKS cluster is created with `local_account_disabled = true` and Entra ID (Azure AD) RBAC (`infra/terraform/modules/aks/main.tf`), so `kubectl` can only talk to it through the `kubelogin` credential plugin. The devcontainer ships `kubectl` and the Azure CLI but not `kubelogin`, so `scripts/deploy-azure.sh` and `scripts/set-k8s-secrets.sh` (both run `az aks get-credentials` and then `kubectl`) cannot work against AKS from inside the container.

## What Changes

- Install `kubelogin` in the devcontainer image with `az aks install-cli`, pinned through a new `KUBELOGIN_VERSION` build argument.
- Install only `kubelogin`: the pinned `kubectl` v1.34.1 stays as it is and is not overwritten by the command's own kubectl download.
- Document `kubelogin` in the toolchain section of `.devcontainer/README.md`, and mark the AKS-through-kubelogin path as untested (`VERIFY`).
- The main `README.md` prerequisites already mention `kubelogin` (done outside this change).
- Out of scope: choosing and testing the kubelogin login mode (device code vs. Azure CLI token via `kubelogin convert-kubeconfig`); recorded as an open question.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `devcontainer-environment`: the deployment-toolchain requirement gains `kubelogin`, so the container can authenticate `kubectl` to the Entra-ID-only AKS cluster.

## Impact

- `.devcontainer/Dockerfile`: new `ARG KUBELOGIN_VERSION` and one `RUN` step; adds a build-time network dependency on `github.com` (kubelogin release download).
- `.devcontainer/README.md`: toolchain list and "what was tested" notes.
- Image rebuild required; no change to `devcontainer.json`, volumes, scripts or Terraform.
- `az aks install-cli` does not verify a checksum, which differs from the other tools in the Dockerfile (see design).
