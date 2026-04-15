import { test, expect } from '@playwright/test';
import { goto, nav, expectVisible } from './helpers';

test.describe('Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
    await nav(page, 'nav-dashboard');
  });

  test('shows service sidebar and stats', async ({ page }) => {
    await expect(page.locator('[data-testid="svc-item-0"]')).toBeVisible();
    await expectVisible(page, 'PostgreSQL');
    await expectVisible(page, 'CPU');
    await expectVisible(page, 'Memory');
  });

  test('service selection updates content', async ({ page }) => {
    await page.click('[data-testid="svc-item-1"]');
    await expectVisible(page, 'Redis');
  });

  test('Logs tab (default)', async ({ page }) => {
    await expect(page.locator('[data-testid="dash-tab-logs"]')).toHaveClass(/active/);
    await expectVisible(page, 'database system is ready');
  });

  test('Config tab', async ({ page }) => {
    await page.click('[data-testid="dash-tab-config"]');
    await expectVisible(page, 'Configuration');
    await expectVisible(page, 'max_connections');
  });

  test('Connection tab', async ({ page }) => {
    await page.click('[data-testid="dash-tab-connection"]');
    await expectVisible(page, 'Connection Details');
    await expectVisible(page, 'Connection string');
  });

  test('Cell tab', async ({ page }) => {
    await page.click('[data-testid="dash-tab-cell"]');
    await expectVisible(page, 'Isolation Cell');
    await expectVisible(page, 'Cell active');
  });

  test('Backups tab', async ({ page }) => {
    await page.click('[data-testid="dash-tab-backups"]');
    await expectVisible(page, 'Backups');
    await expectVisible(page, 'Create Backup Now');
    await expectVisible(page, 'Backup History');
  });

  test('Start All / Stop All buttons', async ({ page }) => {
    await expect(page.locator('[data-testid="start-all"]')).toBeVisible();
    await expect(page.locator('[data-testid="stop-all"]')).toBeVisible();
  });
});
