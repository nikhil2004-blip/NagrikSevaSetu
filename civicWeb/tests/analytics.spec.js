import { test, expect } from '@playwright/test';

test.describe('Analytics Page', () => {
  test.beforeEach(async ({ page }) => {
    // Inject logged in state
    await page.addInitScript(() => {
      window.__PLAYWRIGHT_TEST__ = true;
      window.__PLAYWRIGHT_MOCK_USER__ = { id: 'admin1', name: 'Test Admin', email: 'admin@test.com', role: 'admin' };
    });

    // Mock analytics endpoint
    await page.route('**/api/complaints/stats**', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: {
            totals: {
              total: 15,
              resolved: 10,
              pending: 5,
              highUrgency: 2,
              pendingHighUrgency: 1
            },
            resolutionStats: {
              avgHours: 24,
              minHours: 1,
              maxHours: 48
            },
            byCategory: [
              { _id: 'Water', total: 10, resolved: 8, pending: 2, high: 1 },
              { _id: 'Road', total: 5, resolved: 2, pending: 3, high: 1 }
            ],
            byDay: [
              { _id: '2023-10-01', count: 5, resolved: 2, pending: 3 },
              { _id: '2023-10-02', count: 10, resolved: 8, pending: 2 }
            ],
            byUrgency: [
              { _id: 'High', count: 2 },
              { _id: 'Medium', count: 10 },
              { _id: 'Low', count: 3 }
            ]
          }
        })
      });
    });

    await page.goto('/analytics');
  });

  test('should display analytics charts and data', async ({ page }) => {
    // Check if the page title loads
    await expect(page.locator('h1', { hasText: 'Analytics' })).toBeVisible();

    // KPI values
    await expect(page.getByText('15', { exact: true })).toBeVisible(); // Total
    await expect(page.getByText('5', { exact: true })).toBeVisible();  // Pending
    await expect(page.getByText('10', { exact: true })).toBeVisible(); // Resolved
  });
});
