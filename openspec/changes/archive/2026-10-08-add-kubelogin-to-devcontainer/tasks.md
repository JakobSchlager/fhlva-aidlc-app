## 1. Dockerfile

- [x] 1.1 Look up the kubelogin release to pin on the upstream releases page and add `ARG KUBELOGIN_VERSION` next to the other tool versions
- [x] 1.2 Add a `RUN` step after the Azure CLI install that runs `az aks install-cli --client-version ${KUBECTL_VERSION} --install-location /tmp/kubectl-unused/kubectl --kubelogin-version ${KUBELOGIN_VERSION} --kubelogin-install-location /usr/local/bin/kubelogin`, then removes `/tmp/kubectl-unused`
- [x] 1.3 Update the Dockerfile comments: note that this install has no checksum check and why `az aks install-cli` was used

## 2. Verification

- [x] 2.1 Build the image and confirm it succeeds without `az login`
- [x] 2.2 In the built image, confirm `kubelogin --version` reports the pinned version and `kubectl version --client` still reports the pinned `KUBECTL_VERSION`
- [x] 2.3 Confirm the checksum-verified kubectl is unchanged (v1.34.1 reports correctly; its sha256 equals the published dl.k8s.io checksum)

## 3. Documentation

- [x] 3.1 Add kubelogin to the toolchain list in `.devcontainer/README.md`
- [x] 3.2 In `.devcontainer/README.md`, add a `> **VERIFY:**` note that `az aks get-credentials` followed by `kubectl` against AKS through kubelogin has not been run from the container, and that the login mode is undecided
- [x] 3.3 Confirm the main `README.md` kubelogin prerequisite is consistent with the devcontainer README
