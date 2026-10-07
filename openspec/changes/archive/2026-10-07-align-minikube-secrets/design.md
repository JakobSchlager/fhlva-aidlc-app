## Context

The charts (all four Spring services) read `beer-tracker-secrets` via `envFrom`; auth-service additionally mounts the `auth-rs256-private-key` key as a file at `/etc/secrets`. `deploy-azure.sh` (working, frozen) creates that Secret with keys `auth-rs256-private-key`, `SPRING_DATASOURCE_PASSWORD`, `INTERNAL_API_KEY`. `deploy-minikube.sh` instead creates four `beer-tracker-<service>-secrets` with dashed keys, and `set-k8s-secrets.sh` writes `beer-tracker-secrets` with six dashed keys. Neither works with the charts:

- the minikube Secret name is never referenced, so pods hit `CreateContainerConfigError`;
- dashed keys are not valid env var names, so `envFrom` skips them even under the right Secret name;
- `values-minikube.yaml` lacks `AUTH_PRIVATE_KEY_PATH`, which `application.yml` requires without a default.

All services use one Postgres user (`postgres`) and one password, so a single `SPRING_DATASOURCE_PASSWORD` is sufficient. The health-notification and statistics `application.yml` files read `DB_URL`/`DB_PASSWORD`; Spring relaxed binding should let `SPRING_DATASOURCE_*` env vars override those properties (Azure appears to rely on this) but this has not been verified on minikube.

## Goals / Non-Goals

**Goals:**
- Minikube pods reach Ready using the same Secret name and key set as Azure.
- `set-k8s-secrets.sh` produces a Secret the charts can consume.
- Specs and README match reality.

**Non-Goals:**
- Any change to `deploy-azure.sh`, `charts/` or `values-azure.yaml`.
- Per-service DB users/passwords or a shared secret-creation helper.
- Other drift in `deploy-minikube.sh` (e.g. the stale `eval $(minikube docker-env)` wording in the images requirement).

## Decisions

1. **Mirror the Azure model rather than change the charts.** Charts are shared with Azure, so editing them risks the working deployment. Alternative (per-service Secrets with chart templating) rejected: needs chart changes and a different key scheme on Azure.
2. **Reuse the Azure key names exactly.** Env-var-valid names (`SPRING_DATASOURCE_PASSWORD`, `INTERNAL_API_KEY`) are what the services read. Alternative (keep dashed keys and map with `env.valueFrom`) rejected: requires template changes.
3. **Duplicate the snippet in both scripts.** A shared helper would mean editing `deploy-azure.sh`. Accepted cost: the two snippets must be kept in sync by hand; the spec states the key set so drift is reviewable.
4. **Single `SECRET_DB_PASSWORD` input in `set-k8s-secrets.sh`.** Matches the single DB password in `deploy-azure.sh`. Alternative (keep four prompts and collapse them) rejected as misleading.
5. **Delete `secretsProvider: local` from `values-minikube.yaml`** instead of leaving it: no chart reads it, and the spec requirement is removed.
6. **Minikube `.env` mapping:** `POSTGRES_PASSWORD` → `SPRING_DATASOURCE_PASSWORD`; `INTERNAL_API_KEY` unchanged; key file content → `auth-rs256-private-key`. Existing `.env` variables are unchanged, so no `.env.example` change.

## Risks / Trade-offs

- [Relaxed-binding assumption for health-notification/statistics] → verify on minikube; if the password is not picked up, treat as a finding and decide separately (fix would be in the services, not the Azure path).
- [Operators with automation using the four `SECRET_*_DB_PASSWORD` variables] → documented as breaking in the proposal and README; script fails fast on an empty value rather than silently using an old name.
- [Existing minikube clusters hold the stale per-service Secrets] → harmless but orphaned; tasks include a note to delete them.
- [Manual duplication drifts again] → spec requires identical name/keys on both paths.

## Migration Plan

1. Merge the change.
2. Existing minikube users: re-run `scripts/deploy-minikube.sh`; optionally delete the four old `beer-tracker-*-service-secrets` Secrets by name.
3. Operators of `set-k8s-secrets.sh`: switch to `SECRET_DB_PASSWORD`; re-run, then `kubectl rollout restart deployment -n beer-tracker`.
4. Rollback: revert the commit; Azure is unaffected either way.

## Open Questions

- Should `set-k8s-secrets.sh` also accept the old per-service `SECRET_*_DB_PASSWORD` variables with a deprecation warning? Default here: no, fail clean.
