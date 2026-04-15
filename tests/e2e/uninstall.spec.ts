import { test, expect } from '@playwright/test';
import { goto, nav, expectVisible } from './helpers';

test.describe('Uninstall', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
    await nav(page, 'nav-uninstall');
  });

  test('shows uninstall screen with toggle options', async ({ page }) => {
    await expectVisible(page, 'Uninstall rawenv');
    await expectVisible(page, 'Remove rawenv binary');
    await expectVisible(page, 'Remove installed packages');
    await expectVisible(page, 'Stop and remove services');
    await expectVisible(page, 'Remove service data');
    await expectVisible(page, 'Remove configuration');
    await expectVisible(page, 'Remove DNS and proxy');
  });

  test('has cancel and confirm buttons', async ({ page }) => {
    await expect(page.locator('[data-testid="uninstall-cancel"]')).toBeVisible();
    await expect(page.locator('[data-testid="uninstall-confirm"]')).toBeVisible();
  });

  test('toggle options are clickable', async ({ page }) => {
    const toggles = page.locator('.uninstall-option .toggle');
    const count = await toggles.count();
    expect(count).toBe(6);
    // Click first toggle to flip it
    await toggles.first().click();
  });
});
