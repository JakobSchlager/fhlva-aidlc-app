#!/usr/bin/env bash
# Copy third-party images into minikube from the devcontainer's own image store.
#
# Usage:
#   ./scripts/preload-images.sh IMAGE...
#
# Each image is pulled into the devcontainer's Podman once (its storage is a volume that survives
# `minikube delete`) and then loaded into minikube (`minikube image load`, no network). After a
# `minikube delete`, the next setup loads these images again without downloading them.
# Names must match exactly what the pods ask for, including the registry, for example
# registry-1.docker.io/bitnami/postgresql:latest, otherwise the node pulls the image anyway.
#
# Without a local Podman/Docker it does nothing (the node then pulls as usual).
set -euo pipefail

[[ $# -ge 1 ]] || { sed -n '2,12p' "$0" | sed 's/^# \?//'; exit 1; }

ENGINE=""
for e in podman docker; do
  if command -v "$e" >/dev/null 2>&1 && "$e" info >/dev/null 2>&1; then ENGINE="$e"; break; fi
done
[[ -n "$ENGINE" ]] || { echo "preload-images: no local Podman/Docker, skipping"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for image in "$@"; do
  if "$ENGINE" image exists "$image" 2>/dev/null || "$ENGINE" image inspect "$image" >/dev/null 2>&1; then
    echo "==> $image (cached)"
  else
    echo "==> $image (pull once)"
    "$ENGINE" pull -q "$image" >/dev/null
  fi
  "$ENGINE" save -o "$TMP/image.tar" "$image"
  minikube image load "$TMP/image.tar"
  rm -f "$TMP/image.tar"
done
