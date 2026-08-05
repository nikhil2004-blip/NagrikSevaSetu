import { test, expect } from '@playwright/test';

test.describe('Complaint Detail Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Inject logged in state
    await page.addInitScript(() => {
      window.__PLAYWRIGHT_TEST__ = true;
      window.__PLAYWRIGHT_MOCK_USER__ = { id: 'admin1', name: 'Test Admin', email: 'admin@test.com', role: 'admin' };
    });

    // Mock the specific complaint fetch
    await page.route('**/api/complaints/comp1', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: {
            _id: 'comp1',
            category: 'Water',
            urgency: 'Medium',
            status: 'Pending',
            description: 'Water leak',
            createdAt: new Date().toISOString(),
            userId: { name: 'Citizen One', phone: '1112223333' },
            location: { coordinates: [77.123, 12.345] },
            imageUrl: 'https://via.placeholder.com/150',
            upvotes: 5,
          }
        })
      });
    });

    // Mock status update endpoint
    await page.route('**/api/complaints/comp1/status', async (route) => {
      if (route.request().method() === 'PATCH') {
        const postData = JSON.parse(route.request().postData());
        
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            data: {
              _id: 'comp1',
              status: postData.status,
              category: 'Water',
              urgency: 'Medium',
              description: 'Water leak'
            }
          })
        });
      } else {
        await route.continue();
      }
    });

    await page.goto('/complaints/comp1');
  });

  test('should display complaint details correctly', async ({ page }) => {
    await expect(page.locator('text=Water leak')).toBeVisible();
    await expect(page.locator('h3', { hasText: 'Water Issue' })).toBeVisible(); // Category
    await expect(page.locator('text=Citizen One')).toBeVisible();
    await expect(page.getByText('Lat: 12.345000')).toBeVisible();
    await expect(page.locator('text=Pending').first()).toBeVisible();
    await expect(page.locator('img[alt="Evidence"]')).toBeVisible();
  });

  test('should allow changing complaint status to In Progress', async ({ page }) => {
    // Locate the select dropdown for status
    // Click the 'Mark In Progress' button from the Official Actions panel
    await page.click('button:has-text("Mark In Progress")');
    const updateBtn = page.locator('button', { hasText: /update status|save/i });
    if (await updateBtn.isVisible()) {
      await updateBtn.click();
    }
    
    // Verify toast or new status
    await expect(page.locator('text=Status updated to "In Progress"')).toBeVisible();
  });
});
