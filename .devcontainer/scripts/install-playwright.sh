#!/usr/bin/env bash
# Opt-in: install Chromium for the Playwright e2e suite (not part of the base image, design D9).
#
# `npx playwright install --with-deps chromium` does not work in this image: Playwright's --with-deps
# installs system libraries with apt-get, and this image is Fedora ("your OS is not officially supported ...
# installing dependencies for ubuntu24.04-x64 as a fallback", then "apt-get: command not found").
# So the browser is installed without --with-deps and the shared libraries it needs come from dnf.
# The libraries are what `ldd` reported as missing for the headless Chromium of Playwright 1.62.1; a newer
# Playwright may need more, which the final check reports.
#
# Usage, from the repository root:  devcontainer-install-playwright
set -eu
E2E="${E2E_DIR:-$PWD/e2e}"
[ -f "$E2E/package.json" ] || { echo "devcontainer-install-playwright: no e2e/package.json under $PWD (run from the repo root, or set E2E_DIR)" >&2; exit 1; }

# Fonts are required too, and nothing complains if they are missing: without any font Chromium lays text out
# with zero height, so Playwright treats text elements as hidden (`toBeVisible` fails, screenshots show boxes
# without text). Observed on Windows; reproduced here (paragraph height 0 and not visible before, 18 px and
# visible after installing these two packages).
dnf -y install alsa-lib at-spi2-atk at-spi2-core atk dbus-libs libX11 libXcomposite libXdamage \
               libXext libXfixes libXrandr libxcb mesa-libgbm nspr nss nss-util \
               liberation-fonts dejavu-sans-fonts \
               cups-libs cairo pango
# cups-libs, cairo and pango: not needed by the headless shell, but by the full Chromium that
# `playwright install chromium` also downloads (ldd on aarch64, Playwright 1.62.1); without them Playwright
# prints a "missing dependencies" warning.

cd "$E2E"
[ -d node_modules/@playwright/test ] || npm ci
npx playwright install chromium

# Check both binaries. The headless shell is chrome-headless-shell on x86_64 but headless_shell on aarch64.
ROOT="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"
HEADLESS="$(find "$ROOT" \( -name chrome-headless-shell -o -name headless_shell \) -type f 2>/dev/null | head -1)"
FULL="$(find "$ROOT" -path '*/chromium-*' -name chrome -type f 2>/dev/null | head -1)"
[ -n "$HEADLESS" ] || { echo "devcontainer-install-playwright: browser binary not found after install" >&2; exit 1; }
for BIN in "$HEADLESS" $FULL; do
  if missing="$(ldd "$BIN" 2>&1 | grep 'not found')"; then
    echo "devcontainer-install-playwright: browser installed but libraries are still missing for $BIN:" >&2
    echo "$missing" >&2; exit 1
  fi
done
echo "devcontainer-install-playwright: Chromium and its libraries are installed ($HEADLESS)"
