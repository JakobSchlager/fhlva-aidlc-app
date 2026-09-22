# Local Development Secrets

Place your local development RSA private key as `auth-rs256-private-key.pem` in this directory.

The auth-service uses this key to sign JWTs. The corresponding public key is served via the JWKS endpoint so that other services can verify tokens.

## Generating a key for local development

```bash
openssl genrsa -out secrets/auth-rs256-private-key.pem 2048
```

Run this command from the **repo root** so the file lands at the correct path.

## Environment variables

All other required environment variables (database passwords, internal API key, etc.) are documented in `.env.example` at the repo root. Copy it to `.env` and fill in the values before starting any scenario.

## How the key is used across deployment scenarios

The same RSA key file is used in all three scenarios; only the delivery mechanism differs:

| Scenario | How the key is delivered |
|---|---|
| **Podman Compose / Docker Compose** | `secrets/auth-rs256-private-key.pem` is bind-mounted read-only into the `auth-service` container at `/run/secrets/auth-private-key`. |
| **minikube** | `scripts/deploy-minikube.sh` reads the key from `.env` (`AUTH_RSA_KEY_PATH`) and stores it in a Kubernetes Secret via `kubectl create secret generic`. The pod consumes it via `secretKeyRef`. |
| **Azure AKS** | `scripts/deploy-azure.sh` reads the key from `AUTH_RSA_KEY_PATH` and stores it in a Kubernetes Secret (`beer-tracker-secrets`). The pod consumes it via a volume mount at `/etc/secrets/`. |

## Important

- **Never commit actual key files.** This directory is gitignored except for this README.
- The `.pem` and `.key` files in this directory are excluded by `.gitignore`.
- Do not use production keys for local development.
- For minikube and Azure, the key path is controlled by the `AUTH_RSA_KEY_PATH` variable in `.env`.
