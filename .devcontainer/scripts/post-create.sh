#!/usr/bin/env bash
# One-time setup after the devcontainer is created. Idempotent: never overwrites existing files.
# Secrets are generated here from scratch; nothing is copied from the host.
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# A bind-mounted checkout is owned by a different uid inside the container, so git refuses to work in it
# ("detected dubious ownership") and scripts/deploy-azure.sh fails on `git rev-parse`. Trust this checkout only.
if ! git config --global --get-all safe.directory | grep -qxF "$PWD"; then
  git config --global --add safe.directory "$PWD"
  echo "post-create: marked $PWD as a safe git directory"
fi

if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 12)/; s/^INTERNAL_API_KEY=.*/INTERNAL_API_KEY=$(openssl rand -hex 12)/" .env
  echo "post-create: created .env from .env.example with generated passwords"
else
  echo "post-create: .env exists, left unchanged"
fi

mkdir -p secrets
if [ ! -f secrets/auth-rs256-private-key.pem ]; then
  openssl genrsa -out secrets/auth-rs256-private-key.pem 2048 2>/dev/null
  echo "post-create: generated secrets/auth-rs256-private-key.pem"
else
  echo "post-create: RSA key exists, left unchanged"
fi

(cd frontend && npm ci)
