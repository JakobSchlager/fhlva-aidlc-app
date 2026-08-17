import { test, expect } from '../fixtures';

test('dashboard renders stat tiles (not empty)', async ({ loggedInPage: page }) => {
  // At least one stat tile should be visible — not a blank page
  await expect(
    page.locator('[data-testid="stat-tile"]').first(),
  ).toBeVisible({ timeout: 10_000 });
});

test('beer entry form is visible on dashboard', async ({ loggedInPage: page }) => {
  await expect(page.getByLabel(/beer name/i)).toBeVisible();
  await expect(page.getByLabel(/volume/i)).toBeVisible();
  await expect(page.getByLabel(/abv/i)).toBeVisible();
});

test('submitting a beer entry causes it to appear in history', async ({ loggedInPage: page }) => {
  const beerName = `TestBeer-${Date.now()}`;

  await page.getByLabel(/beer name/i).fill(beerName);
  await page.getByLabel(/volume/i).fill('500');
  await page.getByLabel(/abv/i).fill('5');
  await page.getByRole('button', { name: /add|log|save|submit/i }).click();

  // Navigate to history and verify the entry appears
  await page.goto('/history');
  await expect(page.getByText(beerName)).toBeVisible({ timeout: 8_000 });
});
