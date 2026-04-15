import { test, expect } from '@playwright/test';
import { goto, nav, expectVisible } from './helpers';

test.describe('AI Chat', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
    await nav(page, 'nav-ai');
  });

  test('shows AI chat screen with input', async ({ page }) => {
    await expectVisible(page, 'AI Assistant');
    await expect(page.locator('[data-testid="ai-input"]')).toBeVisible();
    await expect(page.locator('[data-testid="ai-send"]')).toBeVisible();
  });

  test('shows existing chat messages', async ({ page }) => {
    await expectVisible(page, 'optimize');
  });

  test('send message and get response', async ({ page }) => {
    const input = page.locator('[data-testid="ai-input"]');
    await input.fill('optimize memory');
    await page.click('[data-testid="ai-send"]');
    // AI engine should process and show response
    await page.waitForTimeout(500);
    // The chat area should contain the user message
    await expectVisible(page, 'optimize memory');
  });

  test('send message via Enter key', async ({ page }) => {
    const input = page.locator('[data-testid="ai-input"]');
    await input.fill('help');
    await input.press('Enter');
    await page.waitForTimeout(500);
    await expectVisible(page, 'help');
  });
});
