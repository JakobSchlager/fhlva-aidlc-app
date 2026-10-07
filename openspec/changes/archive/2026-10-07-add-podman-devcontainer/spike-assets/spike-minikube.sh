#!/usr/bin/env bash
# Start a fresh minikube profile "spike" with the plain command (no feature gates), keep the full log.
# --force is needed because minikube runs as root inside this container.
minikube delete -p spike >/dev/null 2>&1
( time minikube start -p spike --driver=podman --container-runtime=containerd --memory=4096 --force ) > /tmp/mk.log 2>&1
echo "minikube exit=$?"
tr -d '\r' < /tmp/mk.log | grep -a -E '^real|^\*|^!|^X|^E[0-9]|Error|error' | grep -av 'kic artifacts' | head -30 | cut -c1-240
echo "full log: /tmp/mk.log (inside the container)"
kubectl wait --for=condition=Ready node/spike --timeout=180s 2>&1 | tail -1
