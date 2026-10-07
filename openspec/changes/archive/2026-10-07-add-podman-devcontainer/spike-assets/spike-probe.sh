#!/usr/bin/env bash
# Probe the app through the ingress controller via a port-forward inside the container.
# Waits until the forward answers, then probes every path twice (an earlier Linux run saw two
# unexplained "000" results; the second pass and the readiness wait help tell a race from a real failure).
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 18080:80 > /tmp/pf.log 2>&1 &
pf=$!
ready=no
for _ in $(seq 1 30); do
  if curl -s -o /dev/null --max-time 3 http://localhost:18080/; then ready=yes; break; fi
  sleep 1
done
echo "port-forward answering: $ready"
for pass in 1 2; do
  for u in / /auth/.well-known/jwks.json /statistics/ /tracking/ /notifications/; do
    printf 'pass %s  %-34s -> ' "$pass" "$u"
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 15 "http://localhost:18080$u"
  done
done
printf 'frontend body (first 80 bytes): '; curl -s --max-time 15 http://localhost:18080/ | head -c 80; echo
kill "$pf" 2>/dev/null
