import { test, expect } from '@playwright/test';
import { goto, nav, expectVisible } from './helpers';

test.describe('Settings', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
    await nav(page, 'nav-settings');
  });

  test('shows settings layout with nav', async ({ page }) => {
    await expect(page.locator('[data-testid="settings-nav-general"]')).toBeVisible();
    await expectVisible(page, 'General');
  });

  test('General page', async ({ page }) => {
    await page.click('[data-testid="settings-nav-general"]');
    await expectVisible(page, 'Store location');
    await expectVisible(page, 'Auto-start services');
  });

  test('Services page', async ({ page }) => {
    await page.click('[data-testid="settings-nav-services"]');
    await expectVisible(page, 'Services');
  });

  test('Runtimes page', async ({ page }) => {
    await page.click('[data-testid="settings-nav-runtimes"]');
    await expectVisible(page, 'Runtimes');
    await expectVisible(page, 'Node.js');
  });

  test('Network page', async ({ page }) => {
    await page.click('[data-testid="settings-nav-network"]');
    await expectVisible(page, 'Network');
    await expectVisible(page, 'DNS Masking');
    await expectVisible(page, 'Reverse Proxy');
    await expectVisible(page, 'Tunneling');
  });

  test('Cells page', async ({ page }) => {
    await page.click('[data-testid="settings-nav-cells"]');
    await expectVisible(page, 'Isolation Cells');
    await expectVisible(page, 'Seatbelt');
  });

  test('Deploy page', async ({ page }) => {
    await page.click('[data-testid="settings-nav-deploy"]');
    await expectVisible(page, 'Deploy');
    await expectVisible(page, 'Default Provider');
  });

  test('AI page', async ({ page }) => {
    await page.click('[data-testid="settings-nav-ai"]');
    await expectVisible(page, 'AI Assistant');
    await expectVisible(page, 'Provider');
  });

  test('Theme page with live preview', async ({ page }) => {
    await page.click('[data-testid="settings-nav-theme"]');
    await expectVisible(page, 'Theme');
    await expectVisible(page, 'Live Preview');
    await expectVisible(page, 'Accent');
    // Verify color picker exists
    await expect(page.locator('input[type="color"]').first()).toBeVisible();
    // Verify range sliders exist
    await expect(page.locator('input[type="range"]').first()).toBeVisible();
  });

  test('Theme page shows contrast warnings', async ({ page }) => {
    await page.click('[data-testid="settings-nav-theme"]');
    // innerHTML scripts don't auto-execute; trigger contrast check manually
    await page.evaluate(() => (window as any).updateContrastWarnings());
    await expect(page.locator('#contrast-warnings')).not.toBeEmpty();
    await expectVisible(page, 'Text on background');
  });

  test('About page', async ({ page }) => {
    await page.click('[data-testid="settings-nav-about"]');
    await expectVisible(page, 'About');
  });

  test('all 9 nav items exist', async ({ page }) => {
    const navItems = ['general', 'services', 'runtimes', 'network', 'cells', 'deploy', 'ai', 'theme', 'about'];
    for (const item of navItems) {
      await expect(page.locator(`[data-testid="settings-nav-${item}"]`)).toBeVisible();
    }
  });
});
