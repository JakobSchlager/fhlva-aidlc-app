#!/usr/bin/env bash
# =============================================================================
# run-local.sh — Run the k6 load driver against the Compose stack
#
# Usage:
#   PROFILE=smoke ./load/run-local.sh [extra k6 run arguments]
#
# Runs grafana/k6 in a container attached to the Compose network and targets
# nginx directly (http://nginx:80), so it behaves the same with Podman and
# Docker, on macOS, Windows and Linux. No local k6 installation needed.
#
# Environment variables passed through to k6 (all optional):
#   PROFILE RATE DURATION SPIKE_FACTOR USERS WRITE_RATIO RUN_NAME SLO_FILE
#   BASE_URL AUTH_URL TRACKING_URL STATISTICS_URL NOTIFICATIONS_URL
#
# Script settings:
#   CONTAINER_ENGINE  podman or docker (default: whichever is installed, podman first)
#   K6_IMAGE          k6 image (default: docker.io/grafana/k6:2.3.0)
#   COMPOSE_NETWORK   network to join (default: the network of the nginx container)
# =============================================================================
set -euo pipefail

LOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K6_IMAGE="${K6_IMAGE:-docker.io/grafana/k6:2.3.0}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,21p' "$0" | sed 's/^# \?//'
  exit 0
fi

# --- Container engine --------------------------------------------------------
ENGINE="${CONTAINER_ENGINE:-}"
if [[ -z "$ENGINE" ]]; then
  if command -v podman &>/dev/null; then ENGINE=podman
  elif command -v docker &>/dev/null; then ENGINE=docker
  else echo "ERROR: neither podman nor docker found" >&2; exit 1
  fi
fi

# --- Compose network ---------------------------------------------------------
# Both podman-compose and docker compose label containers with the service name.
NETWORK="${COMPOSE_NETWORK:-}"
if [[ -z "$NETWORK" ]]; then
  NGINX=$("$ENGINE" ps --filter "label=com.docker.compose.service=nginx" --format '{{.Names}}' | head -n1)
  if [[ -z "$NGINX" ]]; then
    echo "ERROR: no running nginx container from the Compose stack." >&2
    echo "       Start the stack first: podman compose up -d (or docker compose up -d)" >&2
    exit 1
  fi
  NETWORK=$("$ENGINE" inspect "$NGINX" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
fi

export BASE_URL="${BASE_URL:-http://nginx:80}"

ENV_ARGS=()
for var in PROFILE RATE DURATION SPIKE_FACTOR USERS WRITE_RATIO RUN_NAME SLO_FILE \
           BASE_URL AUTH_URL TRACKING_URL STATISTICS_URL NOTIFICATIONS_URL; do
  if [[ -n "${!var:-}" ]]; then ENV_ARGS+=(-e "$var=${!var}"); fi
done

echo "k6: profile=${PROFILE:-smoke} target=$BASE_URL network=$NETWORK image=$K6_IMAGE"
exec "$ENGINE" run --rm -i \
  --network "$NETWORK" \
  -v "$LOAD_DIR:/load:ro" \
  -w /load \
  "$K6_IMAGE" run "${ENV_ARGS[@]}" "$@" /load/script.js
