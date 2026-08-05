import { test, expect } from '@playwright/test';

test.describe('Authentication Flow', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      window.__PLAYWRIGHT_TEST__ = true;
    });
  });

  test('should show login page by default for unauthenticated users', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveURL(/.*\/login/);
    await expect(page.locator('h2')).toContainText('Department Portal Access');
  });

  test('should login as admin and redirect to admin dashboard', async ({ page }) => {
    await page.goto('/login');
    
    // Open login modal
    await page.click('text=Login as Main Officer');
    
    // Fill in mock credentials defined in AuthContext
    await page.fill('input[type="email"]', 'admin@test.com');
    await page.fill('input[type="password"]', 'test1234');
    
    await page.locator('.fixed button:has-text("Login")').click();

    // Wait for redirect
    await expect(page).toHaveURL(/.*\/admin\/dashboard/);
    
    // The sidebar should be visible
    await expect(page.locator('nav').first()).toBeVisible();
    await expect(page.locator('header')).toContainText('Test Admin');
  });

  test('should show error on invalid credentials', async ({ page }) => {
    await page.goto('/login');
    
    await page.click('text=Login as Main Officer');
    
    await page.fill('input[type="email"]', 'wrong@test.com');
    await page.fill('input[type="password"]', 'wrongpass');
    
    await page.locator('.fixed button:has-text("Login")').click();

    // Expect an error toast or message
    await expect(page.getByText('Invalid credentials', { exact: false }).first()).toBeVisible();
  });

  test('should logout successfully', async ({ page }) => {
    // Inject logged in state
    await page.addInitScript(() => {
      window.__PLAYWRIGHT_MOCK_USER__ = { id: 'test', name: 'Test Admin', email: 'admin@test.com', role: 'admin' };
    });

    await page.goto('/admin/dashboard');
    
    // Check we are on dashboard
    await expect(page.locator('header')).toContainText('Test Admin');

    // Click logout button (assuming it has text Logout or an icon we can find)
    // Looking for a button or link containing 'Logout' or similar
    const logoutBtn = page.locator('button[title="Logout"]').first();
    await logoutBtn.click();

    // Verify redirected to login
    await expect(page).toHaveURL(/.*\/login/);
  });
});
