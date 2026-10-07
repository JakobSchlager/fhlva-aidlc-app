#!/usr/bin/env bash
# Run the repo's UNCHANGED scripts/deploy-minikube.sh against the "spike" minikube profile.
# Only the environment variable MINIKUBE_PROFILE is set; the script itself is not modified.
cd /work || exit 1
export MINIKUBE_PROFILE=spike
start=$(date +%s)
./scripts/deploy-minikube.sh > /tmp/deploy.log 2>&1
rc=$?
echo "deploy-minikube.sh exit code: $rc, seconds: $(( $(date +%s) - start ))"
tr -d '\r' < /tmp/deploy.log | grep -a -vE '^\s*$|Rolling tag|techdocs|resourcesPreset|primary.resources|readReplicas.resources|kubernetes.io/docs' | tail -14 | cut -c1-200
echo "full log: /tmp/deploy.log (inside the container)"
echo "--- pods"
kubectl get pods -n beer-tracker --no-headers | awk '{print $1, $2, $3, "restarts=" $4}'
for p in $(kubectl get pods -n beer-tracker --no-headers | awk '{split($2,a,"/"); if (a[1]!=a[2] || $3!="Running") print $1}'); do
  echo "--- not ready: $p"
  kubectl logs -n beer-tracker "$p" --previous 2>&1 | grep -a 'Caused by' | tail -2 | cut -c1-220
  kubectl describe -n beer-tracker pod "$p" | sed -n '/^Events:/,$p' | tail -3 | cut -c1-200
done
exit $rc
