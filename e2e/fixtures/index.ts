import { test as base, expect, type Page } from '@playwright/test';
import { randomUUID } from 'crypto';

export type TestUser = { email: string; password: string };

type Fixtures = {
  testUser: TestUser;
  loggedInPage: Page;
  accessToken: string;
};

// Module-level state shared within a single test run (safe: workers=1)
const authState = { token: '' };

export const test = base.extend<Fixtures>({
  testUser: async ({}, use) => {
    await use({
      email: `test-${randomUUID()}@example.com`,
      password: 'TestPass123!',
    });
  },

  loggedInPage: async ({ page, testUser }, use) => {
    // Register via API so we don't depend on the registration UI working
    const res = await page.request.post('/auth/register', {
      data: { email: testUser.email, password: testUser.password },
    });
    if (!res.ok()) {
      throw new Error(`Fixture registration failed (${res.status()}): ${await res.text()}`);
    }

    // Observe the login response (non-intercepting) to capture the access token.
    // Using waitForResponse avoids route.fulfill's Set-Cookie propagation issues.
    const loginResponsePromise = page.waitForResponse(
      (r) => r.url().endsWith('/auth/login') && r.status() === 200,
      { timeout: 15_000 },
    );

    // Log in via the UI so the React auth context is populated
    await page.goto('/login');
    await page.getByLabel(/email/i).fill(testUser.email);
    await page.getByLabel(/password/i).fill(testUser.password);
    await page.getByRole('button', { name: /log in|sign in/i }).click();

    // Capture access token from the observed response (browser receives it normally)
    const loginResponse = await loginResponsePromise;
    try {
      const json = await loginResponse.json();
      authState.token = json.accessToken ?? '';
    } catch {
      // ignore parse errors — token remains empty string
    }

    await expect(page).toHaveURL(/dashboard/, { timeout: 10_000 }).catch(async () => {
      throw new Error(`Fixture login failed — page URL is ${page.url()}`);
    });

    await use(page);
  },

  // Provides the Bearer access token captured during loggedInPage login.
  // Declare loggedInPage as dependency to guarantee correct setup order.
  accessToken: async ({ loggedInPage: _ }, use) => {
    await use(authState.token);
    authState.token = '';
  },
});

export { expect };
