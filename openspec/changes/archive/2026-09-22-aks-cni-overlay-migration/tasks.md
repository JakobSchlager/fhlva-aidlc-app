## 1. Update AKS Terraform Module

- [x] 1.1 Remove `azurerm_role_assignment.aks_subnet_network_contributor` resource from `infra/terraform/modules/aks/main.tf`
- [x] 1.2 Update `network_profile` block in `azurerm_kubernetes_cluster.main`: add `network_plugin_mode = "overlay"`, change `network_policy` from `"azure"` to `"cilium"`, add `ebpf_data_plane = "cilium"`, add `pod_cidr = "10.244.0.0/16"`

## 2. Validate Terraform Configuration

- [x] 2.1 Run `terraform validate` in `infra/terraform/stages/dev` and confirm no errors
- [x] 2.2 Run `terraform plan` in `infra/terraform/stages/dev` and confirm the plan shows only removal of the role assignment and update of the network profile (no unexpected changes)

## 3. Update the terraform-aks Spec

- [x] 3.1 Sync the delta spec into the main spec: run `openspec sync specs --change "aks-cni-overlay-migration"` to apply the `terraform-aks` delta into `openspec/specs/terraform-aks/spec.md`
- [x] 3.2 Review the updated `openspec/specs/terraform-aks/spec.md` to confirm the role assignment requirement is removed and the network profile requirements reflect overlay + Cilium

## 4. Deploy to Dev Environment

- [x] 4.1 Destroy the existing AKS cluster in dev: `terraform destroy -target=module.aks` in `infra/terraform/stages/dev`
- [x] 4.2 Apply the updated Terraform in dev: `terraform apply` in `infra/terraform/stages/dev` (AKS + network + keyvault applied; role assignments for AGIC and KV services require admin — `roleAssignments/write`)
- [x] 4.3 Verify cluster is running with overlay CNI: `kubectl get nodes -o wide` and `kubectl get pods -A -o wide` — pod IPs should be in `10.244.0.0/16`
- [x] 4.4 Create the `beer-tracker-secrets` Kubernetes Secret in the cluster <!-- Requires task 5 (deploy-azure.sh updated to Terraform) before running the script --> (run `scripts/deploy-azure.sh` or manually: `kubectl create secret generic beer-tracker-secrets --namespace=<ns> --from-literal=auth-rs256-private-key=... --from-literal=auth-db-password=... --from-literal=tracking-db-password=... --from-literal=notifications-db-password=... --from-literal=statistics-db-password=... --from-literal=internal-api-key=...`), then redeploy application workloads via Helm (`helm upgrade --install beer-tracker charts/beer-tracker -f values-azure.yaml ...`) and verify ingress through AGIC is functional
- [x] 4.5 Verify Kubernetes secret injection is working for all services: confirm the `beer-tracker-secrets` secret exists (`kubectl get secret beer-tracker-secrets -n <ns>`), that all pods are Running (`kubectl get pods -A`), and that services can read their expected secrets (e.g. check application logs for DB connection success and successful API key usage)

## 5. Update deploy-azure.sh for Terraform

- [x] 5.1 Remove the `az deployment group create` (Bicep) invocation and the Bicep output-capture block from `scripts/deploy-azure.sh`
- [x] 5.2 Replace captured Bicep outputs with `terraform output` calls from `infra/terraform/stages/dev`: `ACR_LOGIN_SERVER` ← `terraform output -raw acr_login_server`, `AKS_CLUSTER_NAME` ← `terraform output -raw aks_cluster_name`
- [x] 5.3 Verify the updated script succeeds end-to-end: `az acr login`, image build/push, `az aks get-credentials`, k8s secret creation, and Helm deploy all complete against the Terraform-provisioned resources
- [x] 5.4 Add Bitnami PostgreSQL helm install (idempotent) and init SQL step to `deploy-azure.sh` — PostgreSQL is in-cluster, same pattern as minikube
- [x] 5.5 Fix `beer-tracker-secrets` key names in `deploy-azure.sh` to match Spring env var conventions: use `SPRING_DATASOURCE_PASSWORD` (single key for all services) and `INTERNAL_API_KEY` instead of hyphenated keys that Spring cannot bind
- [x] 5.6 Update `values-azure.yaml` with per-service `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `AUTH_PRIVATE_KEY_PATH`, and service interconnect URLs (`JWKS_URI`, `BEER_TRACKING_INTERNAL_URL`)
- [x] 5.7 Add volume mount for `auth-rs256-private-key` secret key in `charts/auth-service/templates/deployment.yaml` so the PEM content is available as a file at `/etc/secrets/auth-rs256-private-key`
- [x] 5.8 Confirm build tooling: Podman 4.9.3 available and Docker-CLI-compatible; `deploy-azure.sh` uses `docker build/push` which Podman fulfils without changes

