import { request } from '@playwright/test';

const BASE_URL = process.env.BASE_URL ?? 'http://localhost:8080';

export default async function globalSetup() {
  const ctx = await request.newContext();
  try {
    const res = await ctx.get(BASE_URL, { timeout: 5000 });
    if (!res.ok() && res.status() !== 404) {
      throw new Error(`Unexpected status ${res.status()}`);
    }
  } catch {
    throw new Error(
      `Stack unreachable at ${BASE_URL} — run "podman compose up" before running E2E tests`,
    );
  } finally {
    await ctx.dispose();
  }
}
