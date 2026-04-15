import { Page, expect } from '@playwright/test';

export async function goto(page: Page) {
  await page.goto('/');
  await page.waitForSelector('#screen-container');
}

export async function nav(page: Page, testid: string) {
  await page.click(`[data-testid="${testid}"]`);
  await page.waitForTimeout(100);
}

export async function expectVisible(page: Page, text: string) {
  await expect(page.getByText(text, { exact: false }).first()).toBeVisible();
}

export async function expectScreen(page: Page, selector: string) {
  await expect(page.locator(selector).first()).toBeVisible();
}
