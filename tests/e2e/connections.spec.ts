import { test, expect } from '@playwright/test';
import { goto, nav, expectVisible } from './helpers';

test.describe('Connections', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
    await nav(page, 'nav-connections');
  });

  test('shows connection manager with cards', async ({ page }) => {
    await expectVisible(page, 'Connection Manager');
    await expectVisible(page, 'DATABASE_URL');
    await expectVisible(page, 'REDIS_URL');
    await expectVisible(page, 'S3_ENDPOINT');
  });

  test('DATABASE_URL has local/remote/proxy toggle', async ({ page }) => {
    await expect(page.locator('[data-testid="conn-remote-db"]')).toBeVisible();
    await expect(page.locator('[data-testid="conn-local-db"]')).toBeVisible();
    await expect(page.locator('[data-testid="conn-proxy-db"]')).toBeVisible();
  });

  test('shows connection badges (local/remote)', async ({ page }) => {
    await expect(page.locator('.badge-local').first()).toBeVisible();
    await expect(page.locator('.badge-remote').first()).toBeVisible();
  });
});
