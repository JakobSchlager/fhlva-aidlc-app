# What did we manage to do during the lab?
Jakob Schlager: Tried to fix networking issue in podman. Refer to the issue section.
Stefan Kastenhofer: Fixed some issues at local service startup. Executed all the load tests locally. 
Pascal Stadler: Connected and tested devcontainer setup on native Linux / Podman. Fixed automated cluster deployment script to auto-start minikube and bypass broken devcontainer Docker credential stores. Configured ingress port-forwarding for web browser access on port 8080. Adapted SLO thresholds from 1000 ms to realistic p95 targets (150 ms / 200 ms) and ran the full k6 test suite in Kubernetes (smoke, baseline, gate, spike, and newcomers).

# Defined & Adapted SLOs
Replaced the initial 1000 ms placeholder targets in `load/slo.json` with realistic p95 thresholds based on measured baseline latency:
- Point reads/creates (`statistics_me`, `statistics_global`, `tracking_create`, `notifications_list`): **p95 < 150 ms**
- Range & aggregation queries (`statistics_trend`, `tracking_list`): **p95 < 200 ms**
- Error budget: **< 1.00%** failed requests (0.00% required for `smoke`)

# Load Test Outcomes
- **Smoke** (1 VU, 30s): Clean run, 100% checks passed, 0 errors, p95 < 73 ms.
- **Baseline** (5 visits/s, 1m): 1,665 requests, 0 errors, all endpoints comfortably met the adapted SLOs (p95 < 90 ms).
- **Gate** (5 visits/s, 30s): 875 requests, 0 errors, all thresholds passed without triggering an early abort.
- **Spike** (2 → 8 visits/s surge, 3.5m): 4,231 requests across 780 iterations, 0 errors (0.00% failure rate) with p95 < 37 ms across all endpoints during peak 4× surge, demonstrating strong resilience.
- **Newcomers** (rapid new user registration & first access): Breached the SLO with a 24.05% error rate. While `auth_register` and `auth_login` were fast (~140–170 ms), first-time stats calculation on cold users (`statistics_me_first`) timed out (>10 s) under concurrent load.
- After completing "newcomers" and immediately starting "gate", it also crossed the threshold 'http_req_failed' due to leftover backend strain and un-warmed caches. Waiting some time and restarting "gate" resulted in a clean run.

# Which issues did we encounter?
- Startup errors because of wrongly generated private key file. File started with " -----BEGIN RSA PRIVATE KEY-----", which could not be parsed correctly. This issue came from the openssl windows tool. When using the wsl openssl command the correct header and footer for the key file were generated.
- Helm deployment in the devcontainer failed with `exit status 255` when fetching Bitnami PostgreSQL: VS Code Remote Containers injected an unreachable `credsStore` (`dev-containers-...`) into `/root/.docker/config.json`. Fixed by adding an automatic fallback to a clean `DOCKER_CONFIG` in `scripts/deploy-minikube.sh`.
- Stale Minikube profile inside the devcontainer prevented cluster startup with a guest provisioning error. Fixed by running `minikube delete` and booting via `devcontainer-minikube-start`.
- Minikube IP (`192.168.49.2`) is only accessible within the container network on Linux. Solved by port-forwarding the ingress controller (`kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80`) to connect from the host browser.
- `load/k8s/run.env` contained a duplicate `SPIKE_FACTOR` key, which caused `kubectl apply -k load/` to reject ConfigMap generation until cleaned up. 
- Podman networking DNS issues. The following error log was received in f.e. the health-notification-service: 
```
... "stack_trace":"org.springframework.security.authentication.AuthenticationServiceException: An error occurred while attempting to decode the Jwt: Couldn't retrieve remote JWK set: org.springframework.web.client.ResourceAccessException: I/O error on GET request for \"http://auth-service:8081/auth/.well-known/jwks.json\": Host is unreachable ...
```

However, curl from inside this container was successfull:
```bash
> curl http://auth-service:8081/auth/.well-known/jwks.json

{"keys":[{"kty":"RSA","use":"sig","alg":"RS256","kid":"auth-service-key-1","n":"0eRlAtAHT26vmgef1EQMEX6m9g-MXjeX8r0vQGrGL-AXPufdb2Y1jTo2U3oVyOrI66kuokFJu0xUBpHG9wR9JfRZf5kZBXeXa3_rqH0GzSPxMUCNK-HWb210Psl9rXZPrhqNwMNo9NX6XuZGmNjgDjxM9DqAtrTBs2dJ0cYrUDn5ZobrVoY83bbYaxK1rzwPSK7v-IVjzrarZL4WgCyhC215gCw6A8OkqIiwS3m2wwUurX9r7hpdvKebFXw5-zQqsVa-OyJLDO6WG4CtZItM4N0i_XUiMxrcNT85eUdTY7oPuM4v2glwC0ERrXmCLQcPTAXFwMA8zHjWfGfVR8Srow","e":"AQAB"}]}/ 
```

It turned out that stale ip addresses were resolved. Curl manages to try both. The service itself probably falls back to the stale entry.

```bash
> curl http://auth-service:8081/auth/.well-known/jwks.json

{"keys":[{"kty":"RSA","use":"sig","alg":"RS256","kid":"auth-service-key-1","n":"0eRlAtAHT26vmgef1EQMEX6m9g-MXjeX8r0vQGrGL-AXPufdb2Y1jTo2U3oVyOrI66kuokFJu0xUBpHG9wR9JfRZf5kZBXeXa3_rqH0GzSPxMUCNK-HWb210Psl9rXZPrhqNwMNo9NX6XuZGmNjgDjxM9DqAtrTBs2dJ0cYrUDn5ZobrVoY83bbYaxK1rzwPSK7v-IVjzrarZL4WgCyhC215gCw6A8OkqIiwS3m2wwUurX9r7hpdvKebFXw5-zQqsVa-OyJLDO6WG4CtZItM4N0i_XUiMxrcNT85eUdTY7oPuM4v2glwC0ERrXmCLQcPTAXFwMA8zHjWfGfVR8Srow","e":"AQAB"}]}/ # curl -v http://auth-service:8081/auth/.well-known/jwks.json
* Host auth-service:8081 was resolved.
* IPv6: (none)
* IPv4: 10.89.0.10, 10.89.0.4
*   Trying 10.89.0.10:8081...
*   Trying 10.89.0.4:8081...
* Established connection to auth-service (10.89.0.4 port 8081) from 10.89.0.7 port 59020
* using HTTP/1.x
> GET /auth/.well-known/jwks.json HTTP/1.1
> Host: auth-service:8081
> User-Agent: curl/8.23.0
> Accept: */*
>
* Request completely sent off
< HTTP/1.1 200
< X-Content-Type-Options: nosniff
< X-XSS-Protection: 0
< Cache-Control: no-cache, no-store, max-age=0, must-revalidate
< Pragma: no-cache
< Expires: 0
< X-Frame-Options: DENY
< Content-Type: application/json
< Content-Length: 437
< Date: Fri, 13 Nov 2026 12:20:45 GMT
<
* Connection #0 to host auth-service:8081 left intact
{"keys":[{"kty":"RSA","use":"sig","alg":"RS256","kid":"auth-service-key-1","n":"0eRlAtAHT26vmgef1EQMEX6m9g-MXjeX8r0vQGrGL-AXPufdb2Y1jTo2U3oVyOrI66kuokFJu0xUBpHG9wR9JfRZf5kZBXeXa3_rqH0GzSPxMUCNK-HWb210Psl9rXZPrhqNwMNo9NX6XuZGmNjgDjxM9DqAtrTBs2dJ0cYrUDn5ZobrVoY83bbYaxK1rzwPSK7v-IVjzrarZL4WgCyhC215gCw6A8OkqIiwS3m2wwUurX9r7hpdvKebFXw5-zQqsVa-OyJLDO6WG4CtZItM4N0i_XUiMxrcNT85eUdTY7oPuM4v2glwC0ERrXmCLQcPTAXFwMA8zHjWfGfVR8Srow","e":"AQAB"}]}/
```
This was not resolved during the lab. It appears that the stale entry corresponds to the ip address of the last container (i.e. after rebuilding, one of the two entries refers to the previous container).

