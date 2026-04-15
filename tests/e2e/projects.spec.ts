import { test, expect } from '@playwright/test';
import { goto, nav, expectVisible } from './helpers';

test.describe('Project Discovery', () => {
  test.beforeEach(async ({ page }) => { await goto(page); });

  test('scan screen shows locations and progress', async ({ page }) => {
    await nav(page, 'nav-discover');
    await expectVisible(page, 'Scanning for projects');
    await expectVisible(page, '~/Projects/');
    await expect(page.locator('[data-testid="scan-view-projects"]')).toBeVisible();
  });

  test('scan → project list', async ({ page }) => {
    await nav(page, 'nav-discover');
    await page.click('[data-testid="scan-view-projects"]');
    await expectVisible(page, 'Discovered Projects');
    await expect(page.locator('[data-testid="project-row"]').first()).toBeVisible();
  });

  test('project list shows all projects with stack tags', async ({ page }) => {
    await nav(page, 'nav-projects');
    const rows = page.locator('[data-testid="project-row"]');
    await expect(rows).toHaveCount(8);
    await expectVisible(page, 'utilio');
    await expectVisible(page, 'Node.js');
  });

  test('project list → setup → installing', async ({ page }) => {
    await nav(page, 'nav-setup');
    await expectVisible(page, 'Environment Setup');
    await expectVisible(page, 'PostgreSQL');
    await expectVisible(page, 'Redis');
    await page.click('[data-testid="setup-apply-btn"]');
    await expectVisible(page, 'Setting up environment');
    // innerHTML scripts don't auto-execute; trigger animation manually
    await page.evaluate(() => {
      (window as any)._setupRan = false;
      let i = 0;
      const t = setInterval(() => {
        const el = document.getElementById('p' + i);
        if (!el || i > 9) {
          clearInterval(t);
          (window as any)._setupRan = false;
          const b = document.getElementById('setup-btn');
          if (b) b.outerHTML = '<button class="btn btn-primary" data-testid="setup-open-dashboard" onclick="navigate(\'gui-dashboard\')">Open Dashboard →</button>';
          return;
        }
        el.className = 'check-done'; el.textContent = '✓';
        const p = document.getElementById('setup-progress');
        if (p) p.style.width = ((i + 1) / 10 * 100) + '%';
        i++;
      }, 50);
    });
    await page.waitForSelector('[data-testid="setup-open-dashboard"]', { timeout: 8000 });
    await page.click('[data-testid="setup-open-dashboard"]');
    await expectVisible(page, 'PostgreSQL');
  });
});
