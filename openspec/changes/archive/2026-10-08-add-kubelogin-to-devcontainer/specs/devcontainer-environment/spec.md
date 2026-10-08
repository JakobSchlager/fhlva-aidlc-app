## MODIFIED Requirements

### Requirement: Devcontainer provides the deployment toolchain at the documented minimum versions
The devcontainer SHALL provide Podman >= 4, kubectl, kubelogin, helm >= 3.10, minikube >= 1.32, terraform >= 1.9 and the Azure CLI >= 2.60, matching the prerequisites stated in the README. kubelogin SHALL be installed at a version pinned in the Dockerfile, and installing it SHALL NOT replace the pinned kubectl.

#### Scenario: Tool versions meet the minimums
- **WHEN** a developer queries the version of each deployment tool inside the container
- **THEN** each reports a version at or above its documented minimum

#### Scenario: kubelogin is available
- **WHEN** a developer runs `kubelogin --version` inside the container
- **THEN** it reports the version pinned in the Dockerfile

#### Scenario: Pinned kubectl is unchanged
- **WHEN** a developer runs `kubectl version --client` inside the container
- **THEN** it reports the kubectl version pinned in the Dockerfile
