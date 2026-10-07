#!/usr/bin/env bash
# Task 1.3: does a compose provider honour `depends_on: condition: service_healthy` for the repo's
# UNCHANGED docker-compose.yml, inside the devcontainer?
#
# Usage (from a terminal in the devcontainer, repo checked out with .env created by post-create):
#   spike-compose-test.sh <podman-compose|docker-compose> [--socket] [--health] [--build-timeout S] [--up-timeout S] [--settle S]
#
#   --socket   start `podman system service` (the Podman API socket) before running the provider
#   --settle S  how long to keep polling the HTTP endpoints for a 200 (default 120)
#   --health   run a background loop that executes `podman healthcheck run` on every container
#              (stand-in for the systemd timers that do this on a normal host)
#
# What it records, per run (also appended to /tmp/spike-compose-results.log):
#   - exit codes of `podman compose build` and `up -d` (124 = hit the timeout, i.e. it hung)
#   - how often Podman actually executed the postgres health check
#   - for each dependent service: started before or after postgres first reported healthy
#   - HTTP status of the frontend and the four actuator health endpoints
# The compose project is always named "spike" and is removed (with volumes) at the end.
set -u

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
PROVIDER="${1:-}"; [ -n "$PROVIDER" ] || usage; shift
SOCKET=no; HEALTH=no; BT=1800; UT=180; SETTLE=120
while [ $# -gt 0 ]; do
  case "$1" in
    --socket) SOCKET=yes ;;
    --health) HEALTH=yes ;;
    --build-timeout) BT="$2"; shift ;;
    --up-timeout) UT="$2"; shift ;;
    --settle) SETTLE="$2"; shift ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac; shift
done
case "$PROVIDER" in podman-compose|docker-compose) ;; *) echo "provider must be podman-compose or docker-compose" >&2; usage ;; esac
command -v "$PROVIDER" >/dev/null || { echo "$PROVIDER is not installed (podman-compose: dnf -y install podman-compose)" >&2; exit 1; }

REPO="${REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO" || exit 1
[ -f docker-compose.yml ] && [ -f .env ] || { echo "run from the repo with docker-compose.yml and .env (created by post-create)" >&2; exit 1; }

# Select the provider explicitly: by default docker-compose wins when it is installed.
# On Fedora, /usr/bin/docker-compose can be docker-compose-switch, a shim that calls `docker compose` and
# loops back into `podman compose` (a fork bomb in the Windows run). Prefer the real binary when it exists.
REAL=/usr/libexec/docker/cli-plugins/docker-compose
if [ "$PROVIDER" = docker-compose ] && [ -x "$REAL" ]; then PROVIDER_BIN="$REAL"; else PROVIDER_BIN="$(command -v "$PROVIDER")"; fi
export PODMAN_COMPOSE_PROVIDER="$PROVIDER_BIN"
export PODMAN_COMPOSE_WARNING_LOGS=false
LOG=/tmp/spike-compose-results.log
FLAGS="socket=$SOCKET health=$HEALTH"
say() { echo "$@" | tee -a "$LOG"; }

SVC_PID=""; HC_PID=""
cleanup() {
  [ -n "$HC_PID" ] && kill "$HC_PID" 2>/dev/null
  podman compose -p spike down -v >/dev/null 2>&1
  [ -n "$SVC_PID" ] && kill "$SVC_PID" 2>/dev/null
}
trap cleanup EXIT

say ""; say "######## $(date -u +%FT%TZ)  provider=$PROVIDER ($("$PROVIDER" --version 2>&1 | grep -a -m1 -E '[0-9]+\.[0-9]+' | tr -d '\r' | cut -c1-80))  $FLAGS"
say "podman: $(podman --version)  cgroup: $(cat /proc/self/cgroup)"
podman compose -p spike down -v >/dev/null 2>&1

if [ "$SOCKET" = yes ]; then
  rm -f /run/podman/podman.sock; mkdir -p /run/podman
  podman system service --time=0 unix:///run/podman/podman.sock >/tmp/podman-service.log 2>&1 &
  SVC_PID=$!; sleep 2
  say "API socket: $([ -S /run/podman/podman.sock ] && echo present || echo MISSING)"
fi
if [ "$HEALTH" = yes ]; then
  ( while true; do for c in $(podman ps -q); do podman healthcheck run "$c" >/dev/null 2>&1; done; sleep 5; done ) &
  HC_PID=$!
fi

t0=$(date +%s)
timeout "$BT" podman compose -p spike build > "/tmp/compose-build-$PROVIDER.log" 2>&1; BRC=$?
say "build: exit=$BRC seconds=$(( $(date +%s) - t0 ))"
[ "$BRC" -ne 0 ] && { say "build log tail:"; tr -d '\r' < "/tmp/compose-build-$PROVIDER.log" | grep -a -vE '^\s*$' | tail -6 | cut -c1-220 | tee -a "$LOG"; }

t1=$(date +%s)
timeout "$UT" podman compose -p spike up -d > "/tmp/compose-up-$PROVIDER.log" 2>&1; URC=$?
say "up -d: exit=$URC seconds=$(( $(date +%s) - t1 ))  (124 = timed out after ${UT}s)"
[ "$URC" -ne 0 ] && { say "up log tail:"; tr -d '\r' < "/tmp/compose-up-$PROVIDER.log" | grep -a -vE '^\s*$' | tail -6 | cut -c1-220 | tee -a "$LOG"; }

say "containers:"
podman ps -a --format '{{.Names}} | {{.Status}}' | grep -E '^spike[-_]' | tee -a "$LOG"

# --- objective ordering evidence --------------------------------------------------------------
# Start time of a container in ns since the epoch, or 0 if it never started. A container that was
# only created has the zero time (year 1), for which UnixNano is undefined, so check the year first.
started_ns() {
  local yr ns raw
  yr=$(podman inspect "$1" --format '{{.State.StartedAt.Year}}' 2>/dev/null)
  if [ -n "$yr" ]; then
    [ "$yr" -lt 2000 ] && { echo 0; return; }
    podman inspect "$1" --format '{{.State.StartedAt.UnixNano}}' 2>/dev/null; return
  fi
  # Template methods not available: fall back to parsing the printed timestamp.
  raw=$(podman inspect "$1" --format '{{.State.StartedAt}}' 2>/dev/null)
  yr=$(date -d "$raw" +%Y 2>/dev/null); ns=$(date -d "$raw" +%s%N 2>/dev/null)
  if [ -z "$yr" ] || [ "$yr" -lt 2000 ]; then echo 0; else echo "$ns"; fi
}
PG=$(podman ps -a --format '{{.Names}}' | grep -E '^spike[-_]postgres[-_]1$' | head -1)
ORDER="N/A"
if [ -n "$PG" ]; then
  RUNS=$(podman inspect "$PG" --format '{{len .State.Health.Log}}' 2>/dev/null || echo "?")
  say "postgres health check executed by Podman: $RUNS time(s) in its log"
  HEALTHY_TS=$(podman inspect "$PG" --format '{{range .State.Health.Log}}{{if eq .ExitCode 0}}{{.End}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | head -1)
  if [ -z "$HEALTHY_TS" ]; then
    say "postgres never reported healthy"; ORDER="NEVER-HEALTHY"
  else
    HEALTHY_NS=$(date -d "$HEALTHY_TS" +%s%N 2>/dev/null)
    say "postgres first healthy at: $HEALTHY_TS"
    ORDER="PASS"
    for svc in auth-service beer-tracking-service health-notification-service statistics-service; do
      C=$(podman ps -a --format '{{.Names}}' | grep -E "^spike[-_]${svc}[-_]1\$" | head -1)
      if [ -z "$C" ]; then say "  $svc: container missing"; ORDER="FAIL"; continue; fi
      NS=$(started_ns "$C")
      RC=$(podman inspect "$C" --format '{{.RestartCount}}' 2>/dev/null); RC=${RC:-0}
      if [ "$RC" -gt 0 ] 2>/dev/null; then
        # restart: unless-stopped re-runs a crashed container, and StartedAt then holds the LAST start,
        # which can be after postgres became healthy even though the first start was too early.
        say "  $svc: restarted $RC time(s); start time is the last start, so ordering is NOT confirmed (works by retry)"
        [ "$ORDER" = PASS ] && ORDER="SUSPECT-RESTARTS"
        continue
      fi
      if [ "$NS" = 0 ]; then
        say "  $svc: never started"; ORDER="FAIL"
      elif [ -n "$HEALTHY_NS" ] && [ "$NS" -ge "$HEALTHY_NS" ]; then
        say "  $svc: started $(( (NS - HEALTHY_NS) / 1000000 )) ms after postgres healthy  -> ok"
      else
        say "  $svc: started $(( (HEALTHY_NS - NS) / 1000000 )) ms BEFORE postgres healthy  -> ORDER VIOLATED"; ORDER="FAIL"
      fi
    done
  fi
fi

say "HTTP probes (inside the devcontainer), polling up to ${SETTLE}s each:"
CODES=""
for u in http://localhost:8080/ http://localhost:8081/actuator/health http://localhost:8082/actuator/health http://localhost:8083/actuator/health http://localhost:8084/actuator/health; do
  p0=$(date +%s); code=000
  while :; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$u")
    [ "$code" = 200 ] && break
    [ $(( $(date +%s) - p0 )) -ge "$SETTLE" ] && break
    sleep 3
  done
  say "  $u -> $code after $(( $(date +%s) - p0 ))s"; CODES="$CODES $code"
done
say "RESULT provider=$PROVIDER $FLAGS build=$BRC up=$URC ordering=$ORDER http=[${CODES# }]"
