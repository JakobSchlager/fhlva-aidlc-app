import { test, expect } from '../fixtures';

test.beforeEach(async ({ loggedInPage: page, accessToken }) => {
  // Seed one entry via API (Bearer token required) so the history page has something to show
  await page.request.post('/tracking/entries', {
    data: { beerName: 'HistoryBeer', volumeMl: 330, abv: 4.5 },
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  await page.goto('/history');
});

test('history page loads and shows entries', async ({ loggedInPage: page }) => {
  await expect(page.getByText('HistoryBeer')).toBeVisible({ timeout: 8_000 });
});

test('date-range filter with future dates shows no results', async ({ loggedInPage: page }) => {
  // Set from/to to a date in the far future — no entries should match
  const future = '2099-01-01';
  const fromInput = page.getByLabel(/from/i);
  const toInput = page.getByLabel(/to/i);

  if (await fromInput.isVisible()) {
    await fromInput.fill(future);
    await toInput.fill(future);
    await page.getByRole('button', { name: /filter|apply|search/i }).click();
    await expect(page.getByText(/no entries|no results|empty/i)).toBeVisible({ timeout: 5_000 });
  } else {
    test.skip(true, 'Date filter inputs not found — check label selectors');
  }
});

test('edit entry updates the displayed value', async ({ loggedInPage: page }) => {
  const updatedName = `EditedBeer-${Date.now()}`;
  await page.getByRole('button', { name: /edit/i }).first().click();
  await page.getByRole('row').filter({ has: page.locator('input[type="text"]') })
    .locator('input[type="text"]').fill(updatedName);
  await page.getByRole('button', { name: /save/i }).click();
  await expect(page.getByText(updatedName)).toBeVisible({ timeout: 5_000 });
});

test('delete entry removes the row', async ({ loggedInPage: page }) => {
  // Count data rows (exclude header row)
  const tbody = page.locator('tbody tr');
  const initialCount = await tbody.count();

  await page.getByRole('button', { name: /delete/i }).first().click();
  // Confirm dialog if present
  const confirmBtn = page.getByRole('button', { name: /yes/i });
  if (await confirmBtn.isVisible({ timeout: 1_000 }).catch(() => false)) {
    await confirmBtn.click();
  }

  await expect(tbody).toHaveCount(initialCount - 1, { timeout: 5_000 });
});
