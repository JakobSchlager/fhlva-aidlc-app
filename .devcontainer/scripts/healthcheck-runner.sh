#!/usr/bin/env bash
# Run Podman health checks inside the devcontainer.
#
# On a normal host Podman schedules a container's health check with systemd. There is no systemd in this
# container (the Dev Containers extension replaces the entrypoint), and in the spike nothing executed the
# checks: a container stayed "starting" with an empty health log, so `depends_on: condition: service_healthy`
# waited forever. This helper runs `podman healthcheck run` for every container that has a health check.
#
# Usage:  devcontainer-healthcheck-runner start|stop|status
#   start   idempotent: does nothing if the runner is already alive. Called from postStartCommand.
#   stop    stops it
#   status  prints whether it is running
#
# Limits (design D11): it ignores each container's --health-interval and polls every $INTERVAL seconds.
# It dies with the container and is started again by postStartCommand on the next start; it is not yet
# tested across a VS Code reconnect or a container restart.
INTERVAL="${HEALTHCHECK_RUNNER_INTERVAL:-5}"
PIDFILE="${HEALTHCHECK_RUNNER_PIDFILE:-/run/devcontainer-healthcheck-runner.pid}"
LOGFILE="${HEALTHCHECK_RUNNER_LOGFILE:-/var/log/devcontainer-healthcheck-runner.log}"

# Alive means: the pid exists AND is our loop. A stale pid file can name an unrelated process after a restart,
# because pids are reused, so check the command line too.
alive() {
  local pid; pid="$(cat "$PIDFILE" 2>/dev/null)" || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'healthcheck-runner.* loop'
}

case "${1:-}" in
  start)
    if alive; then echo "devcontainer-healthcheck-runner: already running (pid $(cat "$PIDFILE"))"; exit 0; fi
    # setsid + nohup: detach from the lifecycle command's session so it keeps running afterwards.
    setsid nohup "$0" loop >> "$LOGFILE" 2>&1 < /dev/null &
    echo $! > "$PIDFILE"
    sleep 1
    if alive; then echo "devcontainer-healthcheck-runner: started (pid $(cat "$PIDFILE"))"
    else echo "devcontainer-healthcheck-runner: WARNING: failed to start, see $LOGFILE" >&2; fi
    ;;
  stop)
    if alive; then kill "$(cat "$PIDFILE")"; rm -f "$PIDFILE"; echo "devcontainer-healthcheck-runner: stopped"
    else echo "devcontainer-healthcheck-runner: not running"; fi
    ;;
  status)
    if alive; then echo "running (pid $(cat "$PIDFILE"))"; else echo "not running"; exit 1; fi
    ;;
  loop)
    # Internal. Only containers that have a health check report one of these three health states.
    while true; do
      for c in $(podman ps -q --filter health=starting --filter health=healthy --filter health=unhealthy 2>/dev/null); do
        podman healthcheck run "$c" > /dev/null 2>&1
      done
      sleep "$INTERVAL"
    done
    ;;
  *)
    echo "usage: $0 start|stop|status" >&2; exit 2 ;;
esac
