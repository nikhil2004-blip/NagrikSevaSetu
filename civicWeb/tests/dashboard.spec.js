import { test, expect } from '@playwright/test';

test.describe('Admin Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    // Inject logged in state
    await page.addInitScript(() => {
      window.__PLAYWRIGHT_TEST__ = true;
      window.__PLAYWRIGHT_MOCK_USER__ = { id: 'admin1', name: 'Test Admin', email: 'admin@test.com', role: 'admin' };
    });

    // Mock the API calls
    await page.route('**/api/complaints/stats', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: {
            totals: { total: 100, pending: 20, inProgress: 10, resolved: 70, highUrgency: 5, pendingHighUrgency: 2 },
            highUrgencyByDept: [{ category: 'Water', count: 2 }]
          }
        })
      });
    });

    await page.route('**/api/complaints?limit=50&sortBy=createdAt', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: [
            {
              _id: 'comp1',
              category: 'Water',
              urgency: 'High',
              status: 'Pending',
              description: 'Water pipe broke on main street',
              createdAt: new Date().toISOString()
            },
            {
              _id: 'comp2',
              category: 'Road',
              urgency: 'Low',
              status: 'In Progress',
              description: 'Small pothole',
              createdAt: new Date(Date.now() - 86400000).toISOString()
            }
          ]
        })
      });
    });

    // We might not need the map route mocked perfectly if map doesn't load without API key, but let's mock it just in case
    await page.route('**/api/complaints/map*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ data: [] })
      });
    });

    await page.goto('/admin/dashboard');
  });

  test('should display dashboard statistics correctly', async ({ page }) => {
    // Check for KPI cards
    await expect(page.locator('text=Total Complaints')).toBeVisible();
    await expect(page.getByText('100', { exact: true })).toBeVisible();
    
    await expect(page.locator('text=Pending').first()).toBeVisible();
    await expect(page.getByText('20', { exact: true })).toBeVisible();

    await expect(page.locator('text=In Progress').first()).toBeVisible();
    await expect(page.getByText('10', { exact: true })).toBeVisible();

    await expect(page.locator('text=Resolved').first()).toBeVisible();
    await expect(page.getByText('70', { exact: true })).toBeVisible();

    // High Urgency Alert Banner
    await expect(page.locator('text=2 pending High Urgency')).toBeVisible();
  });

  test('should display action required list', async ({ page }) => {
    // Wait for the action required list to populate
    await expect(page.locator('text=Water pipe broke on main street')).toBeVisible();
    await expect(page.locator('text=Small pothole')).toBeVisible();

    // Check urgency pills
    await expect(page.locator('span:has-text("High")').first()).toBeVisible();
  });
  
  test('should navigate to complaint detail when clicked', async ({ page }) => {
    // Mock the detail endpoint
    await page.route('**/api/complaints/comp1', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: {
            _id: 'comp1',
            category: 'Water',
            urgency: 'High',
            status: 'Pending',
            description: 'Water pipe broke on main street',
            createdAt: new Date().toISOString(),
            citizenId: { name: 'John Doe', phone: '1234567890' },
            location: { address: 'Main Street' }
          }
        })
      });
    });

    // Click the first action row
    await page.click('text=Water pipe broke on main street');
    
    // Should navigate to detail
    await expect(page).toHaveURL(/.*\/complaints\/comp1/);
    
    // We can also verify something on the complaint detail page
    await expect(page.locator('text=Water pipe broke on main street').first()).toBeVisible();
  });
});
