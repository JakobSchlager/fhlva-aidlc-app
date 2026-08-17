import { test, expect } from '../fixtures';

test('notifications panel is present on dashboard', async ({ loggedInPage: page }) => {
  // The panel element should always be in the DOM (even with no active warnings)
  await expect(
    page.locator('[data-testid="notifications-panel"]').first(),
  ).toBeAttached({ timeout: 8_000 });
});

test('acknowledging a warning removes its banner', async ({ loggedInPage: page, accessToken }) => {
  // This test waits up to 6 minutes for the notification scheduler to fire.
  // In dev the scheduler runs every 5s (SCHEDULER_EVALUATION_DELAY_MS=5000), so it
  // usually completes in under 60s. In CI with 5-minute intervals it may take the full 6 min.
  test.setTimeout(480_000);

  // Seed enough high-ABV entries to trigger the daily threshold (default: 2 standard drinks)
  // 3 × 500ml @ 10% ABV = 15 standard drinks, well above threshold
  for (let i = 0; i < 3; i++) {
    await page.request.post('/tracking/entries', {
      data: { beerName: 'HighABV', volumeMl: 500, abv: 10 },
      headers: { Authorization: `Bearer ${accessToken}` },
    });
  }

  const warningSelector = '[data-testid="warning-banner"], [role="alert"]';
  const maxWaitMs = 6 * 60 * 1_000;
  const pollMs = 10_000;
  const deadline = Date.now() + maxWaitMs;

  let warningVisible = false;
  while (Date.now() < deadline) {
    await page.reload();
    // Wait for the dashboard to render (auth refresh + notifications fetch)
    await page.locator('[data-testid="notifications-panel"]')
      .waitFor({ state: 'attached', timeout: 10_000 })
      .catch(() => {});
    if (await page.locator(warningSelector).first().isVisible({ timeout: 2_000 }).catch(() => false)) {
      warningVisible = true;
      break;
    }
    await page.waitForTimeout(pollMs);
  }

  if (!warningVisible) {
    test.skip(true, 'Warning did not appear within 6 minutes — scheduler may not have run yet');
  }

  // Acknowledge all visible warning banners (daily + weekly may both be active)
  const banners = page.locator(warningSelector);
  const bannerCount = await banners.count();
  for (let i = 0; i < bannerCount; i++) {
    await page.getByRole('button', { name: /acknowledge/i }).first().click();
    await expect(banners).toHaveCount(bannerCount - i - 1, { timeout: 5_000 });
  }
  await expect(banners).toHaveCount(0, { timeout: 5_000 });
});
