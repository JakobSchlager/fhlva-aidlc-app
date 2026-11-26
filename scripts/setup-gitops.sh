#!/usr/bin/env bash
# =============================================================================
# setup-gitops.sh — One-time GitOps setup: two stages, Flux, and the link to your fork
#
# Usage:
#   ./scripts/setup-gitops.sh [--values-file FILE] [--branch BRANCH] [--repo-url URL]
#                             [--build-minikube-images TAG] [--stages "staging prod"]
#
# Run it once per cluster, with kubectl pointing at the cluster. It
#   1. creates the stage namespaces beer-tracker-staging and beer-tracker-prod, each with
#      its own PostgreSQL, initialised databases and the beer-tracker-secrets Secret,
#   2. installs the Flux controllers (pinned version, no bootstrap, no Git token),
#   3. points Flux at your fork (public repository, read-only) and at deploy/stages/,
#   4. waits until both stages are deployed.
# After that, every change to a stage is a commit to deploy/stages/<stage>/helmrelease.yaml.
#
# Options:
#   --values-file FILE            cluster values file (default: values-minikube.yaml on minikube,
#                                 values-azure.yaml otherwise)
#   --branch BRANCH               branch Flux follows (default: the current branch)
#   --repo-url URL                repository Flux pulls (default: the origin remote, as https)
#   --build-minikube-images TAG   build the five images into minikube with this tag first
#   --stages "LIST"               stages to set up (default "staging prod"). "prod" alone is the
#                                 fallback for small laptops (minikube with 4 GiB): one stack instead of two.
#
# Reads POSTGRES_PASSWORD, INTERNAL_API_KEY and AUTH_RSA_KEY_PATH from .env (as deploy-minikube.sh).
# Safe to re-run.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUX_VERSION="v2.9.6"
STAGES=(staging prod)

VALUES_FILE=""
BRANCH=""
REPO_URL=""
BUILD_TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --values-file) VALUES_FILE="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --build-minikube-images) BUILD_TAG="$2"; shift 2 ;;
    --stages) read -r -a STAGES <<< "$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "ERROR: unknown option $1 (see --help)" >&2; exit 1 ;;
  esac
done

# --- Inputs ------------------------------------------------------------------
CONTEXT=$(kubectl config current-context)
if [[ -z "$VALUES_FILE" ]]; then
  if [[ "$CONTEXT" == "minikube" ]]; then VALUES_FILE="values-minikube.yaml"; else VALUES_FILE="values-azure.yaml"; fi
fi
[[ -f "$REPO_ROOT/$VALUES_FILE" ]] || { echo "ERROR: $VALUES_FILE not found in the repository root" >&2; exit 1; }

BRANCH="${BRANCH:-$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)}"
if [[ -z "$REPO_URL" ]]; then
  REPO_URL=$(git -C "$REPO_ROOT" remote get-url origin)
  # git@github.com:owner/repo.git -> https://github.com/owner/repo.git
  if [[ "$REPO_URL" == git@*:* ]]; then
    REPO_URL="https://${REPO_URL#git@}"; REPO_URL="${REPO_URL/://}"
  fi
fi

if ! git -C "$REPO_ROOT" ls-remote --exit-code --heads "$REPO_URL" "$BRANCH" >/dev/null 2>&1; then
  echo "ERROR: branch $BRANCH not found at $REPO_URL. Push it first: git push -u origin $BRANCH" >&2
  exit 1
fi

[[ -f "$REPO_ROOT/.env" ]] || { echo "ERROR: .env not found; copy .env.example and fill it in" >&2; exit 1; }
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"
: "${POSTGRES_PASSWORD:?ERROR: POSTGRES_PASSWORD is not set in .env}"
: "${INTERNAL_API_KEY:?ERROR: INTERNAL_API_KEY is not set in .env}"
RSA_KEY="${AUTH_RSA_KEY_PATH:-secrets/auth-rs256-private-key.pem}"
[[ "$RSA_KEY" == /* ]] || RSA_KEY="$REPO_ROOT/${RSA_KEY#./}"
[[ -f "$RSA_KEY" ]] || { echo "ERROR: RSA private key not found at $RSA_KEY" >&2; exit 1; }

for stage in "${STAGES[@]}"; do
  [[ "$stage" == staging || "$stage" == prod ]] || { echo "ERROR: unknown stage $stage (staging, prod)" >&2; exit 1; }
done
if [[ ${#STAGES[@]} -eq 1 ]]; then STAGES_PATH="./deploy/stages/${STAGES[0]}"; else STAGES_PATH="./deploy/stages"; fi

echo "Cluster:  $CONTEXT"
echo "Source:   $REPO_URL @ $BRANCH"
echo "Values:   $VALUES_FILE"
echo "Flux:     $FLUX_VERSION"
echo "Stages:   ${STAGES[*]} ($STAGES_PATH)"

# --- Images (minikube only) --------------------------------------------------
if [[ -n "$BUILD_TAG" ]]; then
  echo "Building images for minikube with tag $BUILD_TAG..."
  "$REPO_ROOT/scripts/build-images.sh" "$BUILD_TAG"
fi

# Flux's manifests, downloaded once (also used for the image list below).
FLUX_MANIFEST="$(mktemp)"; trap 'rm -f "$FLUX_MANIFEST"' EXIT
curl -fsSL -o "$FLUX_MANIFEST" "https://github.com/fluxcd/flux2/releases/download/$FLUX_VERSION/install.yaml"

if [[ -n "$BUILD_TAG" ]]; then
  # minikube: third-party images from the devcontainer's cache, so that a new cluster does not
  # download them again (Flux controllers, PostgreSQL, k6; ~450 MB).
  echo "Loading third-party images into minikube..."
  "$REPO_ROOT/scripts/preload-images.sh" \
    $(grep -E '^\s+image: ' "$FLUX_MANIFEST" | awk '{print $2}' | sort -u) \
    registry-1.docker.io/bitnami/postgresql:latest \
    "$(grep -E '^\s+image: .*k6' "$REPO_ROOT/charts/beer-tracker/values.yaml" | awk '{print $2}')"
fi

# --- Stages: namespace, secrets, PostgreSQL ----------------------------------
# PostgreSQL gets requests = limits (QoS Guaranteed). On minikube the node reports the VM's memory,
# not minikube's own limit, so the scheduler can overcommit; the kernel then kills the process with
# the highest OOM score. With Guaranteed QoS that is a JVM (restarts alone), not the stage's database.
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
for stage in "${STAGES[@]}"; do
  ns="beer-tracker-$stage"
  echo "Preparing stage $stage (namespace $ns)..."
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  # Dynatrace build label propagation: DT_RELEASE_STAGE from the pod's namespace (the value is a fieldPath).
  kubectl annotate namespace "$ns" mapping.release.dynatrace.com/stage=metadata.namespace --overwrite >/dev/null

  kubectl create secret generic beer-tracker-secrets \
    --namespace="$ns" \
    --from-literal=auth-rs256-private-key="$(cat "$RSA_KEY")" \
    --from-literal=SPRING_DATASOURCE_PASSWORD="$POSTGRES_PASSWORD" \
    --from-literal=INTERNAL_API_KEY="$INTERNAL_API_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

  if ! helm status postgresql --namespace="$ns" &>/dev/null; then
    helm install postgresql bitnami/postgresql \
      --namespace="$ns" \
      --set auth.postgresPassword="$POSTGRES_PASSWORD" \
      --set auth.username=postgres \
      --set primary.resourcesPreset=none \
      --set primary.resources.requests.cpu=250m --set primary.resources.limits.cpu=250m \
      --set primary.resources.requests.memory=256Mi --set primary.resources.limits.memory=256Mi \
      --wait --timeout=5m
  fi
  kubectl exec -i -n "$ns" postgresql-0 -- \
    env PGPASSWORD="$POSTGRES_PASSWORD" psql -q -U postgres \
    < "$REPO_ROOT/postgres-init/init.sql"
done

# --- Flux --------------------------------------------------------------------
echo "Installing Flux $FLUX_VERSION..."
kubectl apply -f "$FLUX_MANIFEST" >/dev/null
kubectl -n flux-system wait deployment --all --for=condition=Available --timeout=5m

echo "Pointing Flux at $REPO_URL ($BRANCH)..."
kubectl apply -f - <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: beer-tracker
  namespace: flux-system
spec:
  interval: 1m
  url: $REPO_URL
  ref:
    branch: $BRANCH
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: beer-tracker-stages
  namespace: flux-system
spec:
  interval: 5m
  path: $STAGES_PATH
  prune: true
  sourceRef:
    kind: GitRepository
    name: beer-tracker
  postBuild:
    substitute:
      CLUSTER_VALUES: $VALUES_FILE
EOF

# --- Wait --------------------------------------------------------------------
echo "Waiting for Flux to deploy both stages (first install can take several minutes)..."
kubectl -n flux-system wait kustomization/beer-tracker-stages --for=condition=Ready --timeout=5m
for stage in "${STAGES[@]}"; do
  kubectl -n "beer-tracker-$stage" wait helmrelease/beer-tracker --for=condition=Ready --timeout=20m
done

cat <<EOF

GitOps setup complete. Flux now follows $BRANCH at $REPO_URL.

Status:
  kubectl get gitrepository,kustomizations -n flux-system
  kubectl get helmreleases -A
  kubectl get events -n beer-tracker-staging --field-selector involvedObject.kind=HelmRelease

Release: edit deploy/stages/<stage>/helmrelease.yaml, commit, push (or merge a PR).
Flux checks the branch every minute.
EOF
