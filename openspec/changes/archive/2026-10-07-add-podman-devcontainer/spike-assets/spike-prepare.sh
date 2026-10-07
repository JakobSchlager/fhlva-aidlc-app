#!/usr/bin/env bash
# Create throwaway secrets inside the container for the checked-out repo in /work.
# Never copies host secrets; values are random and are not printed.
set -eu
cd /work
[ -f .env.example ] || { echo "spike-prepare: /work/.env.example not found (is the repo extracted to /work?)" >&2; exit 1; }
if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 8)/; s/^INTERNAL_API_KEY=.*/INTERNAL_API_KEY=$(openssl rand -hex 8)/" .env
fi
mkdir -p secrets
[ -f secrets/auth-rs256-private-key.pem ] || openssl genrsa -out secrets/auth-rs256-private-key.pem 2048 2>/dev/null
echo "spike-prepare: .env present, required variables set: $(grep -cE '^(POSTGRES_PASSWORD|INTERNAL_API_KEY|AUTH_RSA_KEY_PATH)=.+' .env)/3; key present: $([ -s secrets/auth-rs256-private-key.pem ] && echo yes || echo no)"
