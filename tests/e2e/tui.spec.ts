import { test, expect } from '@playwright/test';
import { goto, nav, expectVisible } from './helpers';

test.describe('TUI', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
    await nav(page, 'nav-tui');
  });

  test('shows TUI window with services tab', async ({ page }) => {
    await expectVisible(page, 'rawenv');
    await expectVisible(page, 'PostgreSQL');
    await expect(page.locator('[data-testid="tui-tab-services"]')).toHaveClass(/active/);
  });

  test('Services tab shows table', async ({ page }) => {
    await expectVisible(page, 'SERVICE');
    await expectVisible(page, 'PORT');
    await expectVisible(page, 'PID');
  });

  test('Logs tab', async ({ page }) => {
    await page.click('[data-testid="tui-tab-logs"]');
    await expectVisible(page, 'Logs');
    await expectVisible(page, 'database system is ready');
  });

  test('Config tab', async ({ page }) => {
    await page.click('[data-testid="tui-tab-config"]');
    await expectVisible(page, 'Config');
    await expectVisible(page, 'max_connections');
  });

  test('Resources tab', async ({ page }) => {
    await page.click('[data-testid="tui-tab-resources"]');
    await expectVisible(page, 'Resources');
  });

  test('AI Chat tab', async ({ page }) => {
    await page.click('[data-testid="tui-tab-ai-chat"]');
    await expectVisible(page, 'AI');
  });

  test('keyboard navigation j/k moves service selection', async ({ page }) => {
    // Default is service 0 (PostgreSQL)
    await expectVisible(page, 'PostgreSQL');
    await page.keyboard.press('j');
    await page.waitForTimeout(150);
    // After pressing j, service 1 (Redis) should be selected
    const selected = page.locator('.tui-table tr.selected');
    await expect(selected).toContainText('Redis');
    await page.keyboard.press('k');
    await page.waitForTimeout(150);
    const reselected = page.locator('.tui-table tr.selected');
    await expect(reselected).toContainText('PostgreSQL');
  });
});
