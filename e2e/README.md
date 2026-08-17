# Beer Tracker — E2E Tests

Playwright tests that verify the full user journey against the running local stack.

## Prerequisites

The full docker-compose stack must be running before executing tests:

```bash
# from repo root
podman compose up
```

Wait until all services are healthy (auth, tracking, notifications, statistics, nginx, frontend).

## Running tests

```bash
cd e2e
npm install            # first time only — installs Playwright + browsers
npx playwright install chromium   # first time only

npm run test:e2e       # headless (CI-style)
npm run test:e2e:ui    # Playwright UI mode (interactive, great for debugging)
npm run test:e2e:report  # open last HTML report
```

## Test files

| File | Covers |
|---|---|
| `tests/auth.spec.ts` | Registration, login, error cases |
| `tests/dashboard.spec.ts` | Dashboard renders, beer entry form, submit → history |
| `tests/history.spec.ts` | Pagination, date filter, edit, delete |
| `tests/notifications.spec.ts` | Panel presence, acknowledge warning |
| `tests/statistics.spec.ts` | Charts, cachedAt, global stats, PII check |

## Notes

- Tests run serially (`workers: 1`) to avoid auth state conflicts between tests.
- Each test creates a unique user (`test-<uuid>@example.com`) via the `loggedInPage` fixture.
- The notifications test waits up to 6 minutes for the scheduler to trigger a warning — it will `skip` if the warning doesn't appear in time.
- Set `BASE_URL` env var to test against a different stack (e.g. AKS staging): `BASE_URL=https://my-aks-host npm run test:e2e`.
