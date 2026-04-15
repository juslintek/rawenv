import { test, expect } from '@playwright/test';
import { goto, nav, expectVisible } from './helpers';

test.describe('OS Switching', () => {
  test.beforeEach(async ({ page }) => { await goto(page); });

  test('default OS is macOS', async ({ page }) => {
    await expect(page.locator('[data-testid="os-macos"]')).toHaveClass(/active/);
  });

  test('switch to Linux', async ({ page }) => {
    await page.click('[data-testid="os-linux"]');
    await expect(page.locator('[data-testid="os-linux"]')).toHaveClass(/active/);
    await expect(page.locator('[data-testid="os-macos"]')).not.toHaveClass(/active/);
    await expectVisible(page, 'Linux detected');
  });

  test('switch to Windows', async ({ page }) => {
    await page.click('[data-testid="os-windows"]');
    await expect(page.locator('[data-testid="os-windows"]')).toHaveClass(/active/);
    await expectVisible(page, 'Windows detected');
  });

  test('OS switch updates installer content', async ({ page }) => {
    // macOS shows launchd
    await expectVisible(page, 'launchd');
    await page.click('[data-testid="os-linux"]');
    await expectVisible(page, 'systemd');
    await page.click('[data-testid="os-windows"]');
    await expectVisible(page, 'Windows Services');
  });
});

test.describe('Theme Switching', () => {
  test.beforeEach(async ({ page }) => { await goto(page); });

  test('default theme is dark', async ({ page }) => {
    const body = page.locator('body');
    await expect(body).not.toHaveClass(/light/);
  });

  test('switch to light theme', async ({ page }) => {
    await page.click('[data-testid="theme-light"]');
    await expect(page.locator('body')).toHaveClass(/light/);
    await expect(page.locator('[data-testid="theme-light"]')).toHaveClass(/active/);
  });

  test('switch back to dark theme', async ({ page }) => {
    await page.click('[data-testid="theme-light"]');
    await expect(page.locator('body')).toHaveClass(/light/);
    await page.click('[data-testid="theme-dark"]');
    await expect(page.locator('body')).not.toHaveClass(/light/);
  });
});
