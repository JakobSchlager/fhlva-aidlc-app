#!/usr/bin/env bash
# Start minikube inside the devcontainer (default profile, so scripts/deploy-minikube.sh works unchanged).
# The README's plain `minikube start` is not enough here:
#   --driver=podman        nested Podman is the container engine
#   --container-runtime    containerd, as used in the spike
#   --force                minikube runs as root inside the container
# Extra arguments are passed through (for example --memory=6144).
if [ "$(cat /proc/self/cgroup)" = "0::/" ]; then
  echo "devcontainer-minikube-start: this shell is in the container's top-level cgroup, so minikube" >&2
  echo "cannot create resource-limited containers. Run devcontainer-cgroup-init, then open a new terminal." >&2
  exit 1
fi
exec minikube start --driver=podman --container-runtime=containerd --memory=4096 --force "$@"
