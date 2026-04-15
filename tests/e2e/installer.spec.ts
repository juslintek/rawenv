import { test, expect } from '@playwright/test';
import { goto, expectVisible } from './helpers';

test.describe('Installer Flow', () => {
  test.beforeEach(async ({ page }) => { await goto(page); });

  test('welcome screen shows OS detection and Install button', async ({ page }) => {
    await expectVisible(page, 'Install rawenv');
    await expectVisible(page, 'macOS detected');
    await expect(page.locator('[data-testid="installer-install-btn"]')).toBeVisible();
  });

  test('welcome → install animation → done', async ({ page }) => {
    await page.click('[data-testid="installer-install-btn"]');
    await expectVisible(page, 'Installing rawenv...');
    // innerHTML scripts don't auto-execute; trigger animation manually
    await page.evaluate(() => {
      (window as any)._installRan = false;
      let i = 0;
      const t = setInterval(() => {
        const el = document.getElementById('s' + i);
        if (!el || i > 5) {
          clearInterval(t);
          (window as any)._installRan = false;
          const b = document.getElementById('install-btn');
          if (b) b.outerHTML = '<button class="btn btn-primary" data-testid="installer-launch-btn" onclick="installerNext(\'done\')">Launch rawenv →</button>';
          return;
        }
        el.className = 'check-done'; el.textContent = '✓';
        const p = document.getElementById('install-progress');
        if (p) p.style.width = ((i + 1) / 6 * 100) + '%';
        i++;
      }, 50);
    });
    await page.waitForSelector('[data-testid="installer-launch-btn"]', { timeout: 5000 });
    await page.click('[data-testid="installer-launch-btn"]');
    await expectVisible(page, 'rawenv installed');
    await expect(page.locator('[data-testid="installer-continue-btn"]')).toBeVisible();
  });

  test('done screen shows version and continue button', async ({ page }) => {
    await page.click('[data-testid="nav-installer-done"]');
    await expectVisible(page, 'rawenv installed');
    await expectVisible(page, 'rawenv 0.1.0');
    await page.click('[data-testid="installer-continue-btn"]');
    await expectVisible(page, 'Scanning for projects');
  });
});
