#!/usr/bin/env bash
# Let this container's cgroup hand controllers to nested cgroups, so nested Podman and minikube can
# create resource-limited containers (cgroup v2 "no internal processes" rule: a cgroup that holds
# processes cannot enable controllers for its children).
#
# Moves every process in the container's top-level cgroup into /init, then enables the controllers.
# Run from postStartCommand on EVERY start. It is safe to repeat. It deliberately does not rely on
# being PID 1: the Dev Containers extension replaces the container entrypoint.
#
# On failure it warns and exits 0, so a host without cgroup v2 still gets a usable container for
# building and testing; devcontainer-minikube-start then reports the problem clearly.
CG=/sys/fs/cgroup

if [ ! -f "$CG/cgroup.controllers" ]; then
  echo "devcontainer-cgroup-init: WARNING: no cgroup v2 hierarchy at $CG (cgroup.controllers missing)." >&2
  echo "devcontainer-cgroup-init: nested containers and minikube will not work on this host." >&2
  exit 0
fi

# The braces let us silence the shell's own redirection errors; only our warnings are printed.
# One PID per write: a single multi-PID write fails on the first PID that cannot be moved.
if ! { mkdir -p "$CG/init" && xargs -rn1 < "$CG/cgroup.procs" > "$CG/init/cgroup.procs"; } 2>/dev/null; then
  echo "devcontainer-cgroup-init: WARNING: could not move all processes into /init" >&2
fi

if ! { sed -e 's/ / +/g' -e 's/^/+/' < "$CG/cgroup.controllers" > "$CG/cgroup.subtree_control"; } 2>/dev/null; then
  echo "devcontainer-cgroup-init: WARNING: could not enable controllers for nested cgroups" >&2
  exit 0
fi
echo "devcontainer-cgroup-init: nested cgroup delegation enabled ($(tr '\n' ' ' < "$CG/cgroup.subtree_control"))"
