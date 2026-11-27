#!/usr/bin/env bash
# Build Beer Tracker images and push them to Azure Container Registry (AKS counterpart of build-images.sh).
#
# Usage:
#   ./scripts/build-push-acr.sh TAG [SERVICE...] [--acr LOGIN_SERVER]
#
#   TAG       image tag, for example latest or v2. Use a new tag per release: pods only pull
#             a tag they do not already have (pullPolicy IfNotPresent).
#   SERVICE   auth-service, beer-tracking-service, health-notification-service,
#             statistics-service, frontend (default: all five)
#   --acr     registry login server (default: terraform output acr_login_server of
#             infra/terraform/stages/dev)
#
# Needs: az CLI logged in (az login), docker or podman, and AcrPush on the registry.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL=(auth-service beer-tracking-service health-notification-service statistics-service frontend)

[[ $# -ge 1 && "$1" != -* ]] || { sed -n '2,14p' "$0" | sed 's/^# \?//'; exit 1; }
TAG="$1"; shift
SERVICES=(); ACR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --acr) ACR="$2"; shift 2 ;;
    *) SERVICES+=("$1"); shift ;;
  esac
done
[[ ${#SERVICES[@]} -gt 0 ]] || SERVICES=("${ALL[@]}")
[[ -n "$ACR" ]] || ACR=$(terraform -chdir="$REPO_ROOT/infra/terraform/stages/dev" output -raw acr_login_server)

ENGINE=""
for e in docker podman; do
  if command -v "$e" >/dev/null 2>&1 && "$e" info >/dev/null 2>&1; then ENGINE="$e"; break; fi
done
[[ -n "$ENGINE" ]] || { echo "ERROR: neither docker nor podman is available" >&2; exit 1; }

# --expose-token works with both Docker and Podman (as in deploy-azure.sh)
TOKEN=$(az acr login --name "${ACR%%.*}" --expose-token --output tsv --query accessToken)
"$ENGINE" login "$ACR" --username 00000000-0000-0000-0000-000000000000 --password "$TOKEN"

for svc in "${SERVICES[@]}"; do
  [[ " ${ALL[*]} " == *" $svc "* ]] || { echo "ERROR: unknown service $svc (one of: ${ALL[*]})" >&2; exit 1; }
  if [[ "$svc" == frontend ]]; then ctx="$REPO_ROOT/frontend"; else ctx="$REPO_ROOT/services/$svc"; fi
  echo "==> $ACR/$svc:$TAG"
  "$ENGINE" build -t "$ACR/$svc:$TAG" "$ctx"
  "$ENGINE" push "$ACR/$svc:$TAG"
done
