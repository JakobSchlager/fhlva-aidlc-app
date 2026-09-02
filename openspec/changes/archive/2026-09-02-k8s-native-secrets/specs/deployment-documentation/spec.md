## MODIFIED Requirements

### Requirement: Each scenario section includes prerequisites, step-by-step instructions, and verification
For each of the three deployment scenarios, the README SHALL include: a prerequisites list (tools + versions), numbered step-by-step instructions, a verification step confirming the stack is running, and a troubleshooting subsection for the most common failure modes.

#### Scenario: Compose section is self-contained
- **WHEN** a developer reads only the Compose section of the README
- **THEN** they have enough information to start the full stack, verify it is healthy, and resolve the most common startup failures

#### Scenario: Minikube section covers chart-specific steps
- **WHEN** a developer reads the minikube section
- **THEN** they find instructions for: installing minikube, enabling the ingress addon, building images into minikube, creating Kubernetes Secrets, running the deploy script, and accessing the app via `minikube ip`

#### Scenario: Azure section references the manual secret setup script
- **WHEN** a developer reads the Azure section
- **THEN** they find instructions for: creating a service principal, setting environment variables, running `scripts/deploy-azure.sh`, running `scripts/set-k8s-secrets.sh --environment <env>` to populate secrets, setting GitHub Actions Environment secrets, and initialising the PostgreSQL schema. References to `set-keyvault-secrets.sh` or Key Vault setup SHALL NOT appear.
