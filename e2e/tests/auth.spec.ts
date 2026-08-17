import { test, expect } from '../fixtures';
import { randomUUID } from 'crypto';

test('register with valid credentials redirects to dashboard', async ({ page }) => {
  await page.goto('/register');
  await page.getByLabel(/email/i).fill(`test-${randomUUID()}@example.com`);
  await page.getByLabel(/password/i).fill('ValidPass123!');
  await page.getByRole('button', { name: /create account/i }).click();
  await expect(page).toHaveURL(/login|dashboard/, { timeout: 8_000 });
});

test('register with duplicate email shows error', async ({ page, testUser }) => {
  // pre-create the user
  await page.request.post('/auth/register', {
    data: { email: testUser.email, password: testUser.password },
  });

  await page.goto('/register');
  await page.getByLabel(/email/i).fill(testUser.email);
  await page.getByLabel(/password/i).fill(testUser.password);
  await page.getByRole('button', { name: /create account/i }).click();

  await expect(page.getByText(/already|exists|taken|conflict/i)).toBeVisible({ timeout: 5_000 });
  await expect(page).not.toHaveURL(/dashboard/);
});

test('register with short password shows validation error', async ({ page }) => {
  await page.goto('/register');
  await page.getByLabel(/email/i).fill(`test-${randomUUID()}@example.com`);
  await page.getByLabel(/password/i).fill('short');
  await page.getByRole('button', { name: /create account/i }).click();

  await expect(page.getByText(/password|characters|least 8/i)).toBeVisible({ timeout: 5_000 });
  await expect(page).not.toHaveURL(/dashboard/);
});

test('login with valid credentials reaches dashboard', async ({ page, testUser }) => {
  await page.request.post('/auth/register', {
    data: { email: testUser.email, password: testUser.password },
  });

  await page.goto('/login');
  await page.getByLabel(/email/i).fill(testUser.email);
  await page.getByLabel(/password/i).fill(testUser.password);
  await page.getByRole('button', { name: /log in|sign in/i }).click();

  await expect(page).toHaveURL(/dashboard/, { timeout: 8_000 });
});

test('login with wrong password shows error', async ({ page, testUser }) => {
  await page.request.post('/auth/register', {
    data: { email: testUser.email, password: testUser.password },
  });

  await page.goto('/login');
  await page.getByLabel(/email/i).fill(testUser.email);
  await page.getByLabel(/password/i).fill('WrongPassword!');
  await page.getByRole('button', { name: /log in|sign in/i }).click();

  await expect(page.getByText(/invalid|incorrect|wrong|credentials/i)).toBeVisible({ timeout: 5_000 });
  await expect(page).not.toHaveURL(/dashboard/);
});
