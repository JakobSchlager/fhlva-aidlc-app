## ADDED Requirements

### Requirement: README.md is the single entry point for all deployment scenarios
The project SHALL have a top-level `README.md` that introduces the application, lists all three deployment scenarios with links or sections for each, and specifies the prerequisites for each scenario.

#### Scenario: New developer onboarding
- **WHEN** a developer clones the repository and opens `README.md`
- **THEN** they can identify which deployment scenario fits their needs and find all prerequisites listed before any instructions

#### Scenario: README covers all three scenarios
- **WHEN** the README is reviewed
- **THEN** it contains distinct sections for Podman Compose, minikube, and Azure AKS deployments, each self-contained enough to follow without reading the others

### Requirement: Each scenario section includes prerequisites, step-by-step instructions, and verification
For each of the three deployment scenarios, the README SHALL include: a prerequisites list (tools + versions), numbered step-by-step instructions, a verification step confirming the stack is running, and a troubleshooting subsection for the most common failure modes.

#### Scenario: Compose section is self-contained
- **WHEN** a developer reads only the Compose section of the README
- **THEN** they have enough information to start the full stack, verify it is healthy, and resolve the most common startup failures

#### Scenario: Minikube section covers chart-specific steps
- **WHEN** a developer reads the minikube section
- **THEN** they find instructions for: installing minikube, enabling the ingress addon, building images into minikube, creating Kubernetes Secrets, running the deploy script, and accessing the app via `minikube ip`

#### Scenario: Azure section references the deploy script
- **WHEN** a developer reads the Azure section
- **THEN** they find instructions for: creating a service principal, setting environment variables, running `scripts/deploy-azure.sh`, setting GitHub Actions secrets, and initialising the PostgreSQL schema

### Requirement: .env.example documents all required secrets
The repository SHALL contain a `.env.example` file at the project root listing every secret variable required by the compose and minikube scenarios, with a comment per variable explaining what it is and how to generate or obtain it.

#### Scenario: Developer generates local secrets
- **WHEN** a developer reads `.env.example`
- **THEN** they understand what each variable does and can generate appropriate values (e.g., the RSA key generation command is shown inline)

#### Scenario: .env file is gitignored
- **WHEN** a developer creates `.env` from `.env.example`
- **THEN** `git status` does not show `.env` as a tracked or untracked file

### Requirement: Architecture overview included in README
The README SHALL include a brief architecture section describing the five services, their roles, inter-service communication, and the role of PostgreSQL, so readers understand what they are deploying before following the instructions.

#### Scenario: Architecture section present
- **WHEN** the README is opened
- **THEN** an architecture section (text or diagram) describes all five services and their responsibilities before any deployment instructions appear

### Requirement: Troubleshooting section covers cross-scenario issues
The README SHALL include a troubleshooting section covering issues that can occur in any scenario: port conflicts on 8080, RSA key generation, database connection failures, and health probe failures during startup.

#### Scenario: Troubleshooting is findable
- **WHEN** a developer searches the README for "troubleshoot" or "error"
- **THEN** they find a dedicated troubleshooting section with symptom → cause → fix entries
