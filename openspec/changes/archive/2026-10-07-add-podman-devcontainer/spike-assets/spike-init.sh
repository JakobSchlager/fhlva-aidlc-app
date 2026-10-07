#!/usr/bin/env bash
# PID 1 of the spike container: delegate cgroup v2 controllers, then idle (or exec the given command).
# Moves every process in the container's cgroup into /init so the container's own cgroup can
# hand controllers to nested cgroups (cgroup v2 "no internal processes" rule). Mirrors the
# Linux spike's variant B.
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  mkdir -p /sys/fs/cgroup/init
  xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs \
    || echo "spike-init: moving processes to /init failed" >&2
  sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control \
    || echo "spike-init: enabling controllers failed" >&2
else
  echo "spike-init: WARNING no cgroup v2 hierarchy (/sys/fs/cgroup/cgroup.controllers missing)" >&2
fi
if [ "$#" -eq 0 ]; then exec sleep infinity; else exec "$@"; fi
