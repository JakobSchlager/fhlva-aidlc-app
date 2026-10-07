# Windows checklist 3 — verify the real devcontainer from the VS Code UI

Part of the OpenSpec change `add-podman-devcontainer`. Checklists 1 and 2 used a throwaway image and, for checklist 2,
the extension's command-line tool. This one opens the real `.devcontainer/` through the **VS Code UI** and checks the
things nobody has been able to check yet. Background and results so far are in `design.md`, section "Spike Findings".

**You are checking whether it works, not fixing it.** If something fails, copy the exact error text into the results sheet and
carry on with the next part. Parts C to G are independent of each other once Part A and B pass.

**Status of these instructions:** the `.devcontainer/` files were built and partly tested on Linux, non-privileged. Everything
that needs the privileged container (cgroup setup, minikube, the health-check runner doing its job) is untested in this
form. All commands are untested on Windows. Timings quoted are from earlier single runs, as reference only.

## What changed since checklist 2

- `podman-compose` is the only compose provider. `docker-compose` is no longer in the image, so there is no provider setting to make.
- `postStartCommand` now runs `devcontainer-cgroup-init && devcontainer-healthcheck-runner start`: a background process that
  executes Podman health checks, because there is no systemd in the container.
- `post-create` also marks the checkout as a git safe directory (the "dubious ownership" error from your last run).
- New opt-in helper `devcontainer-install-playwright` (`npx playwright install --with-deps` does not work on Fedora).
- A bind-mounted checkout shows the developer's own `.env`, key and Terraform state to the container; the team accepted this.

## 0. Before you start

- [ ] A branch that contains the current `.devcontainer/` and `openspec/changes/add-podman-devcontainer/`.
      > **TODO(Michael):** commit and push it; at the time of writing everything under `.devcontainer/` is untracked.
- [x] VS Code user settings from before: `dev.containers.dockerPath` = `podman`, `dev.containers.mountWaylandSocket` = `false`.
- [x] Rootful machine: `podman info --format "{{.Host.Security.Rootless}}"` prints `false`.
- [x] Remove the old devcontainer built from the previous version, so nothing stale is reused:
      on the host `podman ps -a` (look for a name starting `vsc-`), `podman rm -f <it>`, and `podman rmi` its image.
      Keep the volumes unless you want a cold start.
- [ ] Write down: Windows build, Podman, VS Code, Dev Containers extension versions.

For the commands below, run them in a VS Code terminal **inside** the devcontainer unless it says "on the host".

## A. Open it from the UI and check the automatic setup

- [x] Open the repository folder, then "Dev Containers: Reopen in Container". Record the time to a usable window and any error dialog.
- [x] Extensions view: which of the extensions listed in `devcontainer.json` are installed? Four IDs are marked `VERIFY`
      (`vmware.vscode-boot-dev-pack`, `bradlc.vscode-tailwindcss`, `hashicorp.terraform`, `ms-playwright.playwright`); note any that could not be found.
      NOTE: vmware.vscode-boot-dev-pack is not necessary
- [x] Checks, with expected results:

| Command | Expect |
|---|---|
| `cat /proc/self/cgroup` | `0::/init` (the cgroup setup ran by itself) |
| `devcontainer-healthcheck-runner status` | `running (pid N)`. Note N. |
| `podman run --rm docker.io/library/alpine:3.20 echo nested-ok` | `nested-ok` |
| `podman compose version` | mentions `podman-compose version 1.6.0` and `/usr/bin/podman-compose` |
| `command -v docker-compose; rpm -q docker-compose-switch` | not found / not installed |
| `git rev-parse --short HEAD` | a commit id, **no** "dubious ownership" error |
| `ls -la .env secrets/` | your existing `.env` and key, unchanged; if you had none, freshly generated ones |
| `java -version; mvn -v; node -v; terraform version; az version` | Java 21, Maven 3.9, Node 20, Terraform 1.16, Azure CLI 2.91 |

## B. The compose stack, the way the README describes it

- [x] `podman compose up -d` (no flags, no environment variable). It should return without hanging. Record how long it took, and whether
      images had to be built first (about 12 minutes on the Linux host for a cold build, mostly Maven downloads).
- [x] `podman compose ps` — are all services up? Do the four Spring services show as started after `postgres`?
- [x] In the browser **on the host**: `http://localhost:8080`. Did VS Code forward the port by itself? Does the page load?
- [x] A short functional pass in that page: register a user, log in, record one drink, see it in the history. Note anything that fails.
- [x] Ordering evidence, using the real runner (no helper flag needed now). First `podman compose down`, then:
      ```bash
      T=openspec/changes/add-podman-devcontainer/spike-assets/spike-compose-test.sh
      bash $T podman-compose
      ```
      **Expect `ordering=PASS`**, and all five HTTP probes `200` (the script now polls each for up to 120 s and prints how long it took).
      Last time ports 8083 and 8084 returned `000` 15 s after `up`; write down the seconds-to-200 it now reports.
      If it says `NEVER-HEALTHY`, the runner is not doing its job: record `devcontainer-healthcheck-runner status`, and
      `tail /var/log/devcontainer-healthcheck-runner.log`.
      NOTE: output of this step is
      "######## 2026-10-07T13:01:09Z  provider=podman-compose (podman version 5.8.7)  socket=no health=no
podman: podman version 5.8.7  cgroup: 0::/init
build: exit=0 seconds=495
up -d: exit=0 seconds=5  (124 = timed out after 180s)
containers:
spike_postgres_1 | Up 4 seconds (healthy)
spike_auth-service_1 | Up 1 second
spike_beer-tracking-service_1 | Up 1 second
spike_frontend_1 | Up 1 second
spike_health-notification-service_1 | Up 1 second
spike_statistics-service_1 | Up Less than a second
spike_nginx_1 | Up Less than a second
postgres health check executed by Podman: 1 time(s) in its log
postgres first healthy at: 2026-10-07T13:09:27.772418194Z
  auth-service: started 361 ms after postgres healthy  -> ok
  beer-tracking-service: started 608 ms after postgres healthy  -> ok
  health-notification-service: started 1089 ms after postgres healthy  -> ok
  statistics-service: started 1376 ms after postgres healthy  -> ok
HTTP probes (inside the devcontainer), polling up to 120s each:
  http://localhost:8080/ -> 200 after 1s
  http://localhost:8081/actuator/health -> 200 after 14s
  http://localhost:8082/actuator/health -> 200 after 0s
  http://localhost:8083/actuator/health -> 200 after 0s
  http://localhost:8084/actuator/health -> 200 after 0s
RESULT provider=podman-compose socket=no health=no build=0 up=0 ordering=PASS http=[200 200 200 200 200]"
- [x] Leave nothing running afterwards: `podman compose down`.

## C. Playwright end-to-end tests (opt-in install)

- [x] `podman compose up -d` and wait until `http://localhost:8080` loads.
- [x] From the repository root: `devcontainer-install-playwright`. **Expect** a final line "Chromium and its libraries are installed".
      (Linux, in a fresh container: about 40 s. Running it twice is harmless.)
- [x] `cd e2e && npm run test:e2e`. Record passed/failed counts and any failing test with its error. The suite runs serially.
      Note: 2 pass, 17 fails with the following errors
"1) [chromium] › tests/auth.spec.ts:12:5 › register with duplicate email shows error ──────────────

    Error: expect(locator).toBeVisible() failed

    Locator:  getByText(/already|exists|taken|conflict/i)
    Expected: visible
    Received: hidden
    Timeout:  5000ms

    Call log:
      - Expect "toBeVisible" with timeout 5000ms
      - waiting for getByText(/already|exists|taken|conflict/i)
        14 × locator resolved to <p class="mt-6 text-center text-sm text-gray-500">…</p>
           - unexpected value "hidden"


      21 |   await page.getByRole('button', { name: /create account/i }).click();
      22 |
    > 23 |   await expect(page.getByText(/already|exists|taken|conflict/i)).toBeVisible({ timeout: 5_000 });
         |                                                                  ^
      24 |   await expect(page).not.toHaveURL(/dashboard/);
      25 | });
      26 |
        at /workspaces/fhlva-aidlc-app/e2e/tests/auth.spec.ts:23:66

    attachment #1: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/auth-register-with-duplicate-email-shows-error-chromium/test-failed-1.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    Error Context: test-results/auth-register-with-duplicate-email-shows-error-chromium/error-context.md

  2) [chromium] › tests/auth.spec.ts:27:5 › register with short password shows validation error ────

    Error: expect(locator).toBeVisible() failed

    Locator:  getByText(/password|characters|least 8/i)
    Expected: visible
    Received: hidden
    Timeout:  5000ms

    Call log:
      - Expect "toBeVisible" with timeout 5000ms
      - waiting for getByText(/password|characters|least 8/i)
        14 × locator resolved to <label for="password" class="block text-sm font-medium text-gray-700 mb-1">Password</label>
           - unexpected value "hidden"


      31 |   await page.getByRole('button', { name: /create account/i }).click();
      32 |
    > 33 |   await expect(page.getByText(/password|characters|least 8/i)).toBeVisible({ timeout: 5_000 });
         |                                                                ^
      34 |   await expect(page).not.toHaveURL(/dashboard/);
      35 | });
      36 |
        at /workspaces/fhlva-aidlc-app/e2e/tests/auth.spec.ts:33:64

    attachment #1: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/auth-register-with-short-password-shows-validation-error-chromium/test-failed-1.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    Error Context: test-results/auth-register-with-short-password-shows-validation-error-chromium/error-context.md

  3) [chromium] › tests/auth.spec.ts:37:5 › login with valid credentials reaches dashboard ─────────

    Error: expect(page).toHaveURL(expected) failed

    Expected pattern: /dashboard/
    Received string:  "http://localhost:8080/login"

    Call log:
      - Expect "toHaveURL" with timeout 8000ms
        4 × locator resolved to <html lang="en">…</html>
          - unexpected value "http://localhost:8080/login"
      - Target page, context or browser has been closed


      45 |   await page.getByRole('button', { name: /log in|sign in/i }).click();
      46 |
    > 47 |   await expect(page).toHaveURL(/dashboard/, { timeout: 8_000 });
         |                      ^
      48 | });
      49 |
      50 | test('login with wrong password shows error', async ({ page, testUser }) => {
        at /workspaces/fhlva-aidlc-app/e2e/tests/auth.spec.ts:47:22

    Error Context: test-results/auth-login-with-valid-credentials-reaches-dashboard-chromium/error-context.md

  4) [chromium] › tests/dashboard.spec.ts:3:5 › dashboard renders stat tiles (not empty) ───────────

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/dashboard-dashboard-renders-stat-tiles-not-empty--chromium/error-context.md

  5) [chromium] › tests/dashboard.spec.ts:10:5 › beer entry form is visible on dashboard ───────────

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/dashboard-beer-entry-form-is-visible-on-dashboard-chromium/error-context.md

  6) [chromium] › tests/dashboard.spec.ts:16:5 › submitting a beer entry causes it to appear in history 

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/dashboard-submitting-a-bee-6ab90-ses-it-to-appear-in-history-chromium/error-context.md

  7) [chromium] › tests/history.spec.ts:12:5 › history page loads and shows entries ────────────────

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/history-history-page-loads-and-shows-entries-chromium/error-context.md

  8) [chromium] › tests/history.spec.ts:16:5 › date-range filter with future dates shows no results 

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/history-date-range-filter-with-future-dates-shows-no-results-chromium/error-context.md

  9) [chromium] › tests/history.spec.ts:32:5 › edit entry updates the displayed value ──────────────

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/history-edit-entry-updates-the-displayed-value-chromium/error-context.md

  10) [chromium] › tests/history.spec.ts:41:5 › delete entry removes the row ───────────────────────

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/history-delete-entry-removes-the-row-chromium/error-context.md

  11) [chromium] › tests/notifications.spec.ts:3:5 › notifications panel is present on dashboard ───

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/notifications-notifications-panel-is-present-on-dashboard-chromium/error-context.md

  12) [chromium] › tests/notifications.spec.ts:10:5 › acknowledging a warning removes its banner ───

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/notifications-acknowledging-a-warning-removes-its-banner-chromium/error-context.md

  13) [chromium] › tests/statistics.spec.ts:15:5 › personal stats page renders charts without error 

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/statistics-personal-stats-page-renders-charts-without-error-chromium/error-context.md

  14) [chromium] › tests/statistics.spec.ts:24:5 › personal stats page shows cachedAt timestamp ────

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/statistics-personal-stats-page-shows-cachedAt-timestamp-chromium/error-context.md

  15) [chromium] › tests/statistics.spec.ts:29:5 › global stats page renders key metrics ───────────

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/statistics-global-stats-page-renders-key-metrics-chromium/error-context.md

  16) [chromium] › tests/statistics.spec.ts:37:5 › global stats page shows cachedAt timestamp ──────

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/statistics-global-stats-page-shows-cachedAt-timestamp-chromium/error-context.md

  17) [chromium] › tests/statistics.spec.ts:42:5 › global stats page contains no raw user IDs or emails 

    Error: Fixture login failed — page URL is http://localhost:8080/dashboard

       at ../fixtures/index.ts:55

      53 |
      54 |     await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
    > 55 |       throw new Error(`Fixture login failed — page URL is ${page.url()}`);
         |             ^
      56 |     });
      57 |
      58 |     await use(page);
        at /workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:55:13
        at Object.loggedInPage (/workspaces/fhlva-aidlc-app/e2e/fixtures/index.ts:54:5)

    Error Context: test-results/statistics-global-stats-pa-20ddc-s-no-raw-user-IDs-or-emails-chromium/error-context.md

  17 failed
    [chromium] › tests/auth.spec.ts:12:5 › register with duplicate email shows error ───────────────
    [chromium] › tests/auth.spec.ts:27:5 › register with short password shows validation error ─────
    [chromium] › tests/auth.spec.ts:37:5 › login with valid credentials reaches dashboard ──────────
    [chromium] › tests/dashboard.spec.ts:3:5 › dashboard renders stat tiles (not empty) ────────────
    [chromium] › tests/dashboard.spec.ts:10:5 › beer entry form is visible on dashboard ────────────
    [chromium] › tests/dashboard.spec.ts:16:5 › submitting a beer entry causes it to appear in history 
    [chromium] › tests/history.spec.ts:12:5 › history page loads and shows entries ─────────────────
    [chromium] › tests/history.spec.ts:16:5 › date-range filter with future dates shows no results ─
    [chromium] › tests/history.spec.ts:32:5 › edit entry updates the displayed value ───────────────
    [chromium] › tests/history.spec.ts:41:5 › delete entry removes the row ─────────────────────────
    [chromium] › tests/notifications.spec.ts:3:5 › notifications panel is present on dashboard ─────
    [chromium] › tests/notifications.spec.ts:10:5 › acknowledging a warning removes its banner ─────
    [chromium] › tests/statistics.spec.ts:15:5 › personal stats page renders charts without error ──
    [chromium] › tests/statistics.spec.ts:24:5 › personal stats page shows cachedAt timestamp ──────
    [chromium] › tests/statistics.spec.ts:29:5 › global stats page renders key metrics ─────────────
    [chromium] › tests/statistics.spec.ts:37:5 › global stats page shows cachedAt timestamp ────────
    [chromium] › tests/statistics.spec.ts:42:5 › global stats page contains no raw user IDs or emails 
  2 passed (33.0s)
"
- [x] `podman compose down`.

## D. Does the runner survive?

Record the runner's pid each time (`devcontainer-healthcheck-runner status`).

- [X] **D1, reload.** Command Palette: "Developer: Reload Window". After VS Code reconnects, is the runner still running with the **same** pid?
      Note: yes
- [x] **D2, close and reopen.** Close the VS Code window. On the host: `podman ps` — is the devcontainer still running or was it stopped?
      Note: it was stopped
      Reopen the folder in the container. Is the runner running (new pid expected)? `cat /proc/self/cgroup` still `0::/init`?
      Note: yes
      Does nested `podman run --rm docker.io/library/alpine:3.20 echo nested-ok` still work?
      Note: yes
- [x] **D3, restart behind VS Code's back.** On the host: `podman restart <devcontainer name>`. Then in a new VS Code terminal (reload the
      window if it lost the connection): is the runner running? is `/proc/self/cgroup` `0::/init`? The lifecycle commands may not run on a plain
      restart, so failure here is plausible; record exactly what you see. It tells us what the host-setup guide must say.
      Note: The connection is lost and the VS Code window must be reloaded.

## E. minikube with the wrapper and the unchanged deploy script

- [x] `podman compose down` first (both want port 8080 and memory).
- [x] `devcontainer-minikube-start`. **Expect** the node to reach Ready. Record the time. (Earlier: 72 to 105 s cold, on Windows.)
- [x] `./scripts/deploy-minikube.sh` — the repo's script, no environment variables, no edits. Record the exit code and duration (earlier: 420 s) and
      `kubectl get pods -n beer-tracker`. **Expect** six pods `1/1 Running`, 0 restarts.
- [x] `bash openspec/changes/add-podman-devcontainer/spike-assets/spike-probe.sh`. Record both passes. Earlier runs showed `000` results that moved around between paths; note whether they still appear.
- [ ] Memory, with the application running. Earlier readings disagreed (3.08 GB here, 1.81 GB on Linux), so record both of these:
      - on the host: `podman stats --no-stream <devcontainer name>`
      - in the container: `grep -E '^(anon|file|shmem) ' /sys/fs/cgroup/memory.stat` (anonymous memory versus page cache)
      Note: memory usage on the host - 5.036GB
      in the container 
      - anon 2697588736
      - file 4166684672
      - shmem 71319552
- [ ] `minikube delete` to free the memory.

## F. Other toolchain checks

- [x] `cd infra/terraform/stages/dev && terraform init -backend=false && terraform validate` — expect "The configuration is valid". (Linux: yes.)
      Do **not** run `plan` or `apply`.
- [x] `bash scripts/deploy-azure.sh --help` prints its header, and `docker --version` prints Podman. (Do not run the script itself.)
- [x] Optional, only if you have an Azure account you may use: `az login --use-device-code`, then `az account show`. Then
      "Dev Containers: Rebuild Container" and run `az account show` again: the session should survive in the `-azure` volume until it expires.

## G. Optional: repository in a volume (decision D6)

- [ ] Command Palette: "Dev Containers: Clone Repository in Container Volume...", same repository and branch.
- [ ] Record whether it works. If it fails, record the exact error, then set `dev.containers.dockerSocketPath` to `/run/podman/podman.sock`
      and retry; note which value worked.
      > **VERIFY:** that path is a guess for a rootful Podman machine, not something confirmed.
- [ ] If it works: is `.env` newly generated (not copied from your host)? Does `npm ci` have run for `frontend/`? Does `git rev-parse --short HEAD` work?

## H. Clean up

- [x] `podman compose down`, `minikube delete` if still running. Close the devcontainer.
- [x] Keep the volumes if more tests are coming, otherwise remove them on the host (`podman volume ls`, names end in `-containers`, `-m2`, `-azure`, `-kube`, `-minikube`, `-frontend-node-modules`, `-e2e-node-modules`).

## Results sheet — send this back

| Item | Result |
|---|---|
| Versions: Windows build, Podman, VS Code, Dev Containers | |
| A: time to open, extension IDs not found, error dialogs | |
| A: table checks (any that differ from "expect") | |
| B: `up -d` time; services started after postgres? | |
| B: host browser OK? functional pass OK? | |
| B: `RESULT` line from the test script, seconds-to-200 for 8083 and 8084 | |
| C: install helper output; e2e passed / failed counts and failures | |
| D1: same pid after reload? | |
| D2: container still running after closing? runner, cgroup, nested podman after reopen | |
| D3: runner / cgroup after `podman restart` | |
| E: minikube start time; deploy exit code and duration; pods; probe results | |
| E: `podman stats`, `anon` / `file` figures | |
| F: terraform, deploy-azure --help, optional `az` result | |
| G: repo-in-volume result and which socket path worked | |
| Commands you had to change; anything unexpected, with exact error text | |

> **OPEN QUESTION:** if D3 shows the runner and cgroup setup are lost after a plain restart, the host-setup guide must tell developers to reopen
> through VS Code (or run `devcontainer-cgroup-init` and `devcontainer-healthcheck-runner start`), and we should decide whether that is acceptable.
