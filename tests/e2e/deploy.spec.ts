import { test, expect } from '@playwright/test';
import { goto, nav, expectVisible } from './helpers';

test.describe('Deploy', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
    await nav(page, 'nav-deploy');
  });

  test('shows deploy screen with tabs', async ({ page }) => {
    await expect(page.locator('[data-testid="deploy-tab-terraform"]')).toBeVisible();
    await expect(page.locator('[data-testid="deploy-tab-ansible"]')).toBeVisible();
    await expect(page.locator('[data-testid="deploy-tab-image-build"]')).toBeVisible();
    await expect(page.locator('[data-testid="deploy-tab-deploy-log"]')).toBeVisible();
  });

  test('Terraform tab shows HCL code', async ({ page }) => {
    await page.click('[data-testid="deploy-tab-terraform"]');
    await expectVisible(page, 'hcloud_server');
  });

  test('Ansible tab shows playbook', async ({ page }) => {
    await page.click('[data-testid="deploy-tab-ansible"]');
    await expectVisible(page, 'hosts');
    await expectVisible(page, 'production');
  });

  test('Image Build tab shows Containerfile', async ({ page }) => {
    await page.click('[data-testid="deploy-tab-image-build"]');
    await expectVisible(page, 'FROM');
    await expectVisible(page, 'debian');
  });

  test('Deploy Log tab shows progress', async ({ page }) => {
    await page.click('[data-testid="deploy-tab-deploy-log"]');
    await expectVisible(page, 'Deploy Log');
    await expectVisible(page, 'terraform init');
  });

  test('Copy Config modal from Terraform tab', async ({ page }) => {
    await page.click('[data-testid="deploy-tab-terraform"]');
    await page.click('text=📋 Copy Config');
    await expectVisible(page, 'Copied!');
    await page.click('text=OK');
  });

  test('Deploy Log AI Fix button', async ({ page }) => {
    await page.click('[data-testid="deploy-tab-deploy-log"]');
    await expectVisible(page, 'Redis failed');
    await page.click('text=🤖 AI Fix');
    await expectVisible(page, 'AI fix');
  });
});
