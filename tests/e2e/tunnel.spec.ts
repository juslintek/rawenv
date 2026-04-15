import { test, expect } from '@playwright/test';
import { goto, nav, expectVisible } from './helpers';

test.describe('Tunnel', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
    await nav(page, 'nav-tunnel');
  });

  test('shows tunnel screen with 3 tabs', async ({ page }) => {
    await expect(page.locator('[data-testid^="tunnel-tab-"]')).toHaveCount(3);
  });

  test('Active tab shows tunnel info', async ({ page }) => {
    await expectVisible(page, 'Tunnel');
  });

  test('can switch between all 3 tabs', async ({ page }) => {
    const tabs = page.locator('[data-testid^="tunnel-tab-"]');
    for (let i = 0; i < 3; i++) {
      await tabs.nth(i).click();
      await expect(tabs.nth(i)).toHaveClass(/active/);
    }
  });
});
