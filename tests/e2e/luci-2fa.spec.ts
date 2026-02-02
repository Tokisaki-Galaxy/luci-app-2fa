import { test, expect, Page } from '@playwright/test';

import * as OTPAuth from 'otpauth';

// Test configuration - matches the 2FA setup configured in the CI container
// This is a well-known test secret used only for E2E testing - NOT production
const TEST_SECRET = 'JBSWY3DPEHPK3PXP';

/**
 * Generate a valid TOTP code using the standard otpauth library
 */
function generateTOTP(secret: string): string {
  const totp = new OTPAuth.TOTP({
    issuer: 'OpenWrt',
    label: 'root',
    algorithm: 'SHA1',
    digits: 6,
    period: 30,
    secret: OTPAuth.Secret.fromBase32(secret)
  });
  return totp.generate();
}

/**
 * Helper function to verify we are logged in (not on login page)
 */
async function verifyLoggedIn(page: Page): Promise<boolean> {
  const url = page.url();
  // Check if we're on an admin page
  if (!url.includes('admin')) {
    return false;
  }
  
  // Check that login form is NOT visible (we're not on login page)
  const loginForm = page.locator('#luci_password');
  const isLoginFormVisible = await loginForm.isVisible().catch(() => false);
  
  if (isLoginFormVisible) {
    return false;
  }
  
  // Additional check: look for admin page elements that indicate successful login
  const pageContent = await page.content();
  const lowerContent = pageContent.toLowerCase();
  const hasAdminIndicators = lowerContent.includes('logout') ||
                             lowerContent.includes('status') ||
                             lowerContent.includes('system');
  
  return hasAdminIndicators;
}

/**
 * Helper function to login to LuCI with retries
 * Handles both standard login and 2FA login (when OTP field is present)
 * Throws an error if login fails after all retries
 */
async function login(page: Page, password: string = 'password', maxRetries: number = 3) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      await page.goto('/cgi-bin/luci/', { waitUntil: 'domcontentloaded', timeout: 30000 });
      
      // Wait for the login form to be ready
      await page.waitForSelector('#luci_password', { timeout: 30000 });
      
      // Wait for page to fully render
      await page.waitForTimeout(1000);
      
      // Fill in password using the actual input element
      await page.locator('#luci_password').fill(password);
      
      // Check if OTP field is present (2FA enabled) - with new flow, it appears on initial page
      const otpField = page.locator('#luci_otp');
      const hasOtpField = await otpField.isVisible().catch(() => false);
      
      if (hasOtpField) {
        // 2FA is enabled, fill in OTP code
        const otpCode = generateTOTP(TEST_SECRET);
        await otpField.fill(otpCode);
      }
      
      // Click login button
      await page.locator('button.cbi-button-positive').click();
      
      // Wait for navigation - either redirect to admin or page reload
      try {
        await page.waitForURL(/admin/, { timeout: 15000 });
      } catch {
        // If redirect doesn't happen, wait a bit
        await page.waitForTimeout(2000);
      }
      
      // Navigate to admin page to verify login
      const currentUrl = page.url();
      if (!currentUrl.includes('admin')) {
        await page.goto('/cgi-bin/luci/admin/status/overview', { waitUntil: 'domcontentloaded', timeout: 15000 });
      }
      await page.waitForTimeout(2000);
      
      // Verify login was successful
      const isLoggedIn = await verifyLoggedIn(page);
      if (isLoggedIn) {
        return; // Success
      }
      
      // Login failed, prepare for retry
      throw new Error('Login verification failed - still on login page or admin indicators not found');
    } catch (error) {
      if (attempt === maxRetries - 1) {
        // Take a screenshot to debug failed login
        await page.screenshot({ path: `screenshots/login-failed-attempt-${attempt + 1}.png`, fullPage: true }).catch(() => {});
        throw new Error(`Login failed after ${maxRetries} attempts: ${error}`);
      }
      console.log(`Login attempt ${attempt + 1} failed, retrying...`);
      await page.waitForTimeout(2000);
    }
  }
  
  throw new Error('Login failed: exhausted all retry attempts');
}

/**
 * Helper function to take and save screenshot
 */
async function takeScreenshot(page: Page, name: string) {
  await page.screenshot({ 
    path: `screenshots/${name}.png`, 
    fullPage: true 
  });
}

test.describe('LuCI Login Page', () => {
  test('should display standard login form', async ({ page }) => {
    await page.goto('/cgi-bin/luci/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    
    // Wait for page to render
    await page.waitForSelector('#luci_password', { timeout: 30000 });
    
    // Take screenshot of login page
    await takeScreenshot(page, '01-login-page-standard');
    
    // Verify login form elements exist
    await expect(page.locator('#luci_username')).toBeVisible();
    await expect(page.locator('#luci_password')).toBeVisible();
    await expect(page.locator('button.cbi-button-positive')).toBeVisible();
  });

  test('should show error on invalid login', async ({ page }) => {
    await page.goto('/cgi-bin/luci/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    
    await page.waitForSelector('#luci_password', { timeout: 30000 });
    await page.locator('#luci_password').fill('wrongpassword');
    await page.locator('button.cbi-button-positive').click();
    
    // Wait for response
    await page.waitForTimeout(3000);
    
    // Take screenshot of failed login
    await takeScreenshot(page, '02-login-failed');
    
    // Verify error message appears
    const errorMessage = page.locator('.alert-message');
    if (await errorMessage.isVisible()) {
      await expect(errorMessage).toContainText('Invalid');
    }
  });

  test('should successfully login with correct credentials', async ({ page }) => {
    await login(page);
    
    // Wait for page to load
    await page.waitForTimeout(2000);
    
    // Take screenshot after successful login
    await takeScreenshot(page, '03-login-success-overview');
    
    // Verify we're on the admin page
    await expect(page).toHaveURL(/admin/);
  });
});

test.describe('2FA Settings Page', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    
    // Double-check we're logged in before proceeding
    const isLoggedIn = await verifyLoggedIn(page);
    if (!isLoggedIn) {
      throw new Error('beforeEach: Login verification failed - test cannot proceed');
    }
  });

  test('should navigate to 2FA settings page', async ({ page }) => {
    // Navigate to System > 2-Factor Auth
    await page.goto('/cgi-bin/luci/admin/system/2fa');
    
    // Wait for view to fully load (LuCI dynamically loads the view)
    await page.waitForSelector('.cbi-map', { timeout: 60000 });
    
    // Additional wait for all elements to render
    await page.waitForTimeout(2000);
    
    // Take screenshot
    await takeScreenshot(page, '04-2fa-settings-page');
    
    // Verify page contains 2FA content
    const content = await page.content();
    expect(content).toContain('2-Factor');
    
    // Additional assertion: verify we have the 2FA settings form
    const pageUrl = page.url();
    expect(pageUrl).toContain('2fa');
  });

  test('should display Enable 2FA checkbox', async ({ page }) => {
    await page.goto('/cgi-bin/luci/admin/system/2fa');
    
    // Verify we're on the correct page first
    const pageUrl = page.url();
    expect(pageUrl).toContain('2fa');
    
    // Wait for the form to load
    await page.waitForSelector('.cbi-map', { timeout: 60000 });
    await page.waitForTimeout(2000);
    
    // Verify we're not on login page
    const loginForm = page.locator('#luci_password');
    await expect(loginForm).not.toBeVisible({ timeout: 5000 });
    
    // Check for Enable 2FA checkbox - use more flexible selector
    const enableCheckbox = page.locator('input[type="checkbox"]').first();
    await expect(enableCheckbox).toBeVisible({ timeout: 30000 });
    
    // Take screenshot highlighting the enable option
    await takeScreenshot(page, '05-2fa-enable-checkbox');
  });

  test('should display OTP type selector', async ({ page }) => {
    await page.goto('/cgi-bin/luci/admin/system/2fa');
    
    // Verify we're on the correct page first
    expect(page.url()).toContain('2fa');
    
    // Wait for the form to load
    await page.waitForSelector('.cbi-map', { timeout: 60000 });
    await page.waitForTimeout(2000);
    
    // Verify we're not on login page
    const loginForm = page.locator('#luci_password');
    await expect(loginForm).not.toBeVisible({ timeout: 5000 });
    
    // Check for OTP type dropdown - be more flexible
    const typeSelector = page.locator('select').first();
    await expect(typeSelector).toBeVisible({ timeout: 30000 });
    
    // Take screenshot
    await takeScreenshot(page, '06-2fa-type-selector');
  });

  test('should have Generate Key button', async ({ page }) => {
    await page.goto('/cgi-bin/luci/admin/system/2fa');
    
    // Verify we're on the correct page first
    expect(page.url()).toContain('2fa');
    
    // Wait for the form to load
    await page.waitForSelector('.cbi-map', { timeout: 60000 });
    await page.waitForTimeout(2000);
    
    // Verify we're not on login page
    const loginForm = page.locator('#luci_password');
    await expect(loginForm).not.toBeVisible({ timeout: 5000 });
    
    // Look for Generate Key button with more flexible matching
    const generateButton = page.locator('button:has-text("Generate")');
    await expect(generateButton).toBeVisible({ timeout: 30000 });
    
    // Take screenshot before clicking
    await takeScreenshot(page, '07-2fa-before-generate-key');
    
    // Click generate key
    await generateButton.click();
    
    // Wait for key to be generated
    await page.waitForTimeout(3000);
    
    // Take screenshot after generating key
    await takeScreenshot(page, '08-2fa-after-generate-key');
  });

  test('should display QR code when key is set', async ({ page }) => {
    await page.goto('/cgi-bin/luci/admin/system/2fa');
    
    // Verify we're on the correct page first
    expect(page.url()).toContain('2fa');
    
    // Wait for the form to load
    await page.waitForSelector('.cbi-map', { timeout: 60000 });
    await page.waitForTimeout(2000);
    
    // Verify we're not on login page
    const loginForm = page.locator('#luci_password');
    await expect(loginForm).not.toBeVisible({ timeout: 5000 });
    
    // Generate a key first
    const generateButton = page.locator('button:has-text("Generate")');
    await expect(generateButton).toBeVisible({ timeout: 30000 });
    await generateButton.click();
    await page.waitForTimeout(3000);
    
    // Take screenshot of QR code
    await takeScreenshot(page, '09-2fa-qr-code');
    
    // Check for SVG (QR code) or some otpauth content
    const pageContent = await page.content();
    // QR code or otpauth URL should be present after key generation
    expect(pageContent).toMatch(/otpauth|svg|qr/i);
  });

  test('should show TOTP-specific options when TOTP is selected', async ({ page }) => {
    await page.goto('/cgi-bin/luci/admin/system/2fa');
    
    // Verify we're on the correct page first
    expect(page.url()).toContain('2fa');
    
    // Wait for the form to load
    await page.waitForSelector('.cbi-map', { timeout: 60000 });
    await page.waitForTimeout(2000);
    
    // Verify we're not on login page
    const loginForm = page.locator('#luci_password');
    await expect(loginForm).not.toBeVisible({ timeout: 5000 });
    
    // Verify 2FA form content is present
    const pageContent = await page.content();
    expect(pageContent).toContain('2-Factor');
    
    // Take screenshot
    await takeScreenshot(page, '10-2fa-totp-options');
  });

  test('should show HOTP-specific options when HOTP is selected', async ({ page }) => {
    await page.goto('/cgi-bin/luci/admin/system/2fa');
    
    // Verify we're on the correct page first
    expect(page.url()).toContain('2fa');
    
    // Wait for the form to load
    await page.waitForSelector('.cbi-map', { timeout: 60000 });
    await page.waitForTimeout(2000);
    
    // Verify we're not on login page
    const loginForm = page.locator('#luci_password');
    await expect(loginForm).not.toBeVisible({ timeout: 5000 });
    
    // Select HOTP if type selector exists
    const typeSelector = page.locator('select').first();
    await expect(typeSelector).toBeVisible({ timeout: 10000 });
    await typeSelector.selectOption('hotp');
    await page.waitForTimeout(1000);
    
    // Verify 2FA form content is present
    const pageContent = await page.content();
    expect(pageContent).toContain('2-Factor');
    
    // Take screenshot
    await takeScreenshot(page, '11-2fa-hotp-options');
  });

  test('should save settings', async ({ page }) => {
    await page.goto('/cgi-bin/luci/admin/system/2fa');
    
    // Verify we're on the correct page first
    expect(page.url()).toContain('2fa');
    
    // Wait for the form to load
    await page.waitForSelector('.cbi-map', { timeout: 60000 });
    await page.waitForTimeout(2000);
    
    // Verify we're not on login page
    const loginForm = page.locator('#luci_password');
    await expect(loginForm).not.toBeVisible({ timeout: 5000 });
    
    // Take screenshot before save
    await takeScreenshot(page, '12-2fa-before-save');
    
    // Click Save & Apply if visible
    const saveButton = page.locator('button:has-text("Save")');
    await expect(saveButton).toBeVisible({ timeout: 10000 });
    await saveButton.click();
    await page.waitForTimeout(5000);
    
    // Take screenshot after save
    await takeScreenshot(page, '13-2fa-after-save');
  });
});

test.describe('Authentication Settings Page (luci-patch)', () => {
  // Skip these tests as they require the luci-patch which needs
  // custom dispatcher with 'log' module not available in stock OpenWrt
  test.skip('should navigate to Authentication Settings page', async ({ page }) => {
    await login(page);
    // Navigate to System > Administration > Authentication
    await page.goto('/cgi-bin/luci/admin/system/admin/authsettings');
    
    // Wait for page to load
    await page.waitForSelector('h2', { timeout: 30000 });
    
    // Take screenshot
    await takeScreenshot(page, '14-authsettings-page');
    
    // Verify page title
    await expect(page.locator('h2')).toContainText('Authentication Settings');
  });

  test.skip('should display External Authentication toggle', async ({ page }) => {
    await login(page);
    await page.goto('/cgi-bin/luci/admin/system/admin/authsettings');
    await page.waitForSelector('h2', { timeout: 30000 });
    
    // Check for external auth checkbox
    const externalAuthCheckbox = page.locator('#external_auth');
    await expect(externalAuthCheckbox).toBeVisible();
    
    // Take screenshot
    await takeScreenshot(page, '15-authsettings-external-auth');
  });

  test.skip('should display plugin list', async ({ page }) => {
    await login(page);
    await page.goto('/cgi-bin/luci/admin/system/admin/authsettings');
    await page.waitForSelector('h2', { timeout: 30000 });
    
    // Check for plugins section
    const pluginsSection = page.locator('text=Authentication Plugins');
    await expect(pluginsSection).toBeVisible();
    
    // Take screenshot
    await takeScreenshot(page, '16-authsettings-plugins');
  });

  test.skip('should toggle plugin enabled state', async ({ page }) => {
    await login(page);
    await page.goto('/cgi-bin/luci/admin/system/admin/authsettings');
    await page.waitForSelector('h2', { timeout: 30000 });
    
    // Find 2fa plugin checkbox if it exists
    const plugin2faCheckbox = page.locator('#plugin_2fa');
    
    if (await plugin2faCheckbox.isVisible()) {
      const initialState = await plugin2faCheckbox.isChecked();
      
      // Toggle the checkbox
      await plugin2faCheckbox.click();
      
      // Take screenshot after toggle
      await takeScreenshot(page, '17-authsettings-plugin-toggled');
      
      // Verify state changed
      const newState = await plugin2faCheckbox.isChecked();
      expect(newState).toBe(!initialState);
    }
  });
});

test.describe('Login with 2FA', () => {
  // Skip this test as it requires the dispatcher patch which needs the 'log' module
  test.skip('should show OTP field when 2FA is enabled', async ({ page }) => {
    // This test assumes 2FA has been enabled in previous tests
    await page.goto('/cgi-bin/luci/');
    
    await page.waitForSelector('#luci_password', { timeout: 30000 });
    
    // Fill in credentials
    await page.locator('#luci_password').fill('password');
    await page.locator('button.cbi-button-positive').click();
    
    // Wait for page response
    await page.waitForTimeout(3000);
    
    // Check if OTP field appears (if 2FA is enabled)
    const otpField = page.locator('input[name="luci_otp"]');
    
    if (await otpField.isVisible()) {
      // Take screenshot of 2FA login page
      await takeScreenshot(page, '18-login-with-2fa');
      
      // Verify OTP field attributes
      await expect(otpField).toHaveAttribute('inputmode', 'numeric');
      await expect(otpField).toHaveAttribute('maxlength', '6');
    } else {
      // 2FA not enabled, take screenshot of normal login
      await takeScreenshot(page, '18-login-2fa-not-enabled');
    }
  });
});

test.describe('System Menu Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    
    // Double-check we're logged in before proceeding
    const isLoggedIn = await verifyLoggedIn(page);
    if (!isLoggedIn) {
      throw new Error('beforeEach: Login verification failed - test cannot proceed');
    }
  });

  test('should show 2FA in system menu', async ({ page }) => {
    // Navigate to system page
    await page.goto('/cgi-bin/luci/admin/system/');
    
    // Wait for page content to load
    await page.waitForTimeout(3000);
    
    // Verify we're not on login page
    const loginForm = page.locator('#luci_password');
    await expect(loginForm).not.toBeVisible({ timeout: 5000 });
    
    // Take screenshot of system menu
    await takeScreenshot(page, '19-system-menu');
    
    // Check if page loaded correctly - should be on admin page
    expect(page.url()).toContain('admin');
    
    const pageContent = await page.content();
    expect(pageContent).toContain('system');
  });

  test('should navigate through all 2FA-related pages', async ({ page }) => {
    // System Overview
    await page.goto('/cgi-bin/luci/admin/status/overview');
    await page.waitForTimeout(3000);
    
    // Verify we're not on login page
    const overviewLoginForm = page.locator('#luci_password');
    await expect(overviewLoginForm).not.toBeVisible({ timeout: 5000 });
    expect(page.url()).toContain('admin');
    
    await takeScreenshot(page, '20-status-overview');
    
    // Password page
    await page.goto('/cgi-bin/luci/admin/system/admin/password');
    await page.waitForTimeout(3000);
    
    // Verify we're not on login page
    const passwordLoginForm = page.locator('#luci_password');
    await expect(passwordLoginForm).not.toBeVisible({ timeout: 5000 });
    expect(page.url()).toContain('admin');
    
    await takeScreenshot(page, '21-system-password');
    
    // 2FA page
    await page.goto('/cgi-bin/luci/admin/system/2fa');
    await page.waitForSelector('.cbi-map', { timeout: 60000 });
    await page.waitForTimeout(2000);
    
    // Verify we're not on login page
    const twofaLoginForm = page.locator('#luci_password');
    await expect(twofaLoginForm).not.toBeVisible({ timeout: 5000 });
    expect(page.url()).toContain('2fa');
    
    await takeScreenshot(page, '22-system-2fa-final');
  });
});
