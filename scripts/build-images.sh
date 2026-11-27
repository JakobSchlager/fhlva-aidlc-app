#!/usr/bin/env bash
# Build Beer Tracker images and make them available to minikube.
#
# Usage:
#   ./scripts/build-images.sh TAG [SERVICE...]
#
#   TAG       image tag, for example latest or v2
#   SERVICE   auth-service, beer-tracking-service, health-notification-service,
#             statistics-service, frontend (default: all five)
#
# Examples:
#   ./scripts/build-images.sh latest                      # all five
#   ./scripts/build-images.sh v2 statistics-service       # one service, new tag
#
# Why not `minikube image build`: that builds inside the minikube node, so its layer cache
# (Maven dependencies, base images) is lost with `minikube delete`, and the next build
# downloads everything again (~1.7 GB). This script builds with the devcontainer's own Podman,
# whose storage lives in a volume that survives `minikube delete` and already holds the layers
# from Lab 3's `podman compose build`. The image is then copied into minikube
# (`minikube image load`, no network).
#
# Falls back to `minikube image build` when no local Podman/Docker is available.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL=(auth-service beer-tracking-service health-notification-service statistics-service frontend)

[[ $# -ge 1 && "$1" != -* ]] || { sed -n '2,13p' "$0" | sed 's/^# \?//'; exit 1; }
TAG="$1"; shift
SERVICES=("$@"); [[ ${#SERVICES[@]} -gt 0 ]] || SERVICES=("${ALL[@]}")

ENGINE=""
for e in podman docker; do
  if command -v "$e" >/dev/null 2>&1 && "$e" info >/dev/null 2>&1; then ENGINE="$e"; break; fi
done

context_of() {
  if [[ "$1" == frontend ]]; then echo "$REPO_ROOT/frontend"; else echo "$REPO_ROOT/services/$1"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for svc in "${SERVICES[@]}"; do
  [[ " ${ALL[*]} " == *" $svc "* ]] || { echo "ERROR: unknown service $svc (one of: ${ALL[*]})" >&2; exit 1; }
  ctx="$(context_of "$svc")"
  # Fully qualified, so the name inside minikube is the one the charts use (pullPolicy: Never).
  image="docker.io/library/$svc:$TAG"
  if [[ -n "$ENGINE" ]]; then
    echo "==> $svc:$TAG (build with $ENGINE, then load into minikube)"
    "$ENGINE" build -t "$image" "$ctx"
    "$ENGINE" save -o "$TMP/$svc.tar" "$image"
    minikube image load "$TMP/$svc.tar"
    rm -f "$TMP/$svc.tar"
  else
    echo "==> $svc:$TAG (no local Podman/Docker: minikube image build)"
    minikube image build -t "$svc:$TAG" "$ctx"
  fi
done
echo "Done. In minikube: $(minikube image ls 2>/dev/null | grep -c -E ":$TAG\$" || true) image(s) with tag $TAG."
