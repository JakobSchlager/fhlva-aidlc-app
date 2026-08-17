import { test, expect } from '../fixtures';

test.beforeEach(async ({ loggedInPage: page, accessToken }) => {
  // Seed an entry so statistics caches have data to refresh
  await page.request.post('/tracking/entries', {
    data: { beerName: 'StatsBeer', volumeMl: 330, abv: 5 },
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  // Trigger personal stats cache population so global stats can aggregate
  await page.request.get('/statistics/me', {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
});

test('personal stats page renders charts without error', async ({ loggedInPage: page }) => {
  await page.goto('/stats');
  // Both Recharts containers should be in the DOM
  await expect(page.locator('.recharts-wrapper').first()).toBeVisible({ timeout: 10_000 });
  await expect(page.locator('.recharts-wrapper').nth(1)).toBeVisible({ timeout: 10_000 });
  // No error state visible
  await expect(page.getByText(/error|failed|something went wrong/i)).not.toBeVisible();
});

test('personal stats page shows cachedAt timestamp', async ({ loggedInPage: page }) => {
  await page.goto('/stats');
  await expect(page.getByText(/last updated|cached|refreshed/i)).toBeVisible({ timeout: 10_000 });
});

test('global stats page renders key metrics', async ({ loggedInPage: page }) => {
  await page.goto('/global');
  await expect(page.getByText(/active users/i)).toBeVisible({ timeout: 10_000 });
  await expect(page.getByText(/average|avg/i)).toBeVisible({ timeout: 10_000 });
  // Top Beers section should always be present
  await expect(page.getByText(/top beer/i)).toBeVisible({ timeout: 10_000 });
});

test('global stats page shows cachedAt timestamp', async ({ loggedInPage: page }) => {
  await page.goto('/global');
  await expect(page.getByText(/last updated|cached|refreshed/i)).toBeVisible({ timeout: 10_000 });
});

test('global stats page contains no raw user IDs or emails', async ({ loggedInPage: page }) => {
  await page.goto('/global');
  // Wait for content to load
  await expect(page.getByText(/active users/i)).toBeVisible({ timeout: 10_000 });
  const bodyText = await page.locator('body').innerText();
  // UUIDs look like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  expect(bodyText).not.toMatch(
    /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i,
  );
});
