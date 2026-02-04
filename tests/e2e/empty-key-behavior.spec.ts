/**
 * Empty Key Behavior Test
 * 
 * This test verifies the behavior when 2FA plugin is enabled but the secret key is empty.
 * 
 * Expected Behavior (based on code analysis):
 * - When plugin is enabled globally but key is empty for a user
 * - The is_2fa_enabled() function in auth.d/2fa.uc returns false
 * - Login should succeed with just password (2FA bypassed)
 * 
 * This test answers Question 1: "If the plugin is enabled but the key is empty, 
 * will users be unable to log in?"
 * 
 * Answer: NO - users CAN still log in with just their password when key is empty.
 */

import { test, expect, Page } from '@playwright/test';

const PASSWORD = 'password';

/**
 * Helper: Execute UCI commands in the OpenWrt container
 */
async function execUCI(command: string): Promise<string> {
  const { exec } = await import('child_process');
  const { promisify } = await import('util');
  const execAsync = promisify(exec);
  
  try {
    const { stdout, stderr } = await execAsync(
      `docker exec openwrt-luci sh -c "${command}"`
    );
    if (stderr && !stderr.includes('Warning')) {
      console.error('UCI stderr:', stderr);
    }
    return stdout.trim();
  } catch (error: any) {
    console.error('UCI command failed:', error.message);
    throw error;
  }
}

/**
 * Helper: Set 2FA configuration
 */
async function set2FAConfig(enabled: boolean, key: string = ''): Promise<void> {
  await execUCI(`uci set 2fa.settings.enabled='${enabled ? '1' : '0'}'`);
  await execUCI(`uci set 2fa.root.key='${key}'`);
  await execUCI('uci commit 2fa');
  
  // Restart rpcd to reload configuration
  await execUCI('kill -9 $(pgrep rpcd) 2>/dev/null || true');
  await execUCI('/sbin/rpcd &');
  
  // Wait a moment for rpcd to start
  await new Promise(resolve => setTimeout(resolve, 2000));
}

/**
 * Helper: Take screenshot
 */
async function takeScreenshot(page: Page, name: string) {
  await page.screenshot({ 
    path: `screenshots/empty-key-${name}.png`, 
    fullPage: true 
  });
}

test.describe('Empty Key Behavior - Question 1', () => {
  
  test.beforeAll(async () => {
    // Ensure Docker container is running
    console.log('Setting up test environment...');
  });
  
  test('should allow login with just password when 2FA enabled but key is empty', async ({ page }) => {
    console.log('Test: 2FA enabled globally, but root user has empty key');
    
    // Set 2FA enabled with empty key
    await set2FAConfig(true, '');
    
    // Navigate to login page
    await page.goto('http://localhost:8080/cgi-bin/luci/', { 
      waitUntil: 'domcontentloaded', 
      timeout: 30000 
    });
    
    await takeScreenshot(page, '01-login-page');
    
    // Verify password field is visible
    const passwordField = page.locator('input[name="luci_password"], #luci_password');
    await expect(passwordField).toBeVisible({ timeout: 10000 });
    
    // Verify OTP field is NOT visible (since key is empty, 2FA should be bypassed)
    const otpField = page.locator('input[name="luci_otp"], #luci_otp');
    const otpVisible = await otpField.isVisible().catch(() => false);
    
    console.log('OTP field visible:', otpVisible);
    expect(otpVisible).toBe(false); // OTP should NOT be shown when key is empty
    
    // Fill in password only
    await passwordField.fill(PASSWORD);
    
    await takeScreenshot(page, '02-before-login');
    
    // Submit the form
    const loginButton = page.locator('button[type="submit"], input[type="submit"]').first();
    await loginButton.click();
    
    // Wait for navigation
    await page.waitForLoadState('domcontentloaded', { timeout: 30000 });
    
    await takeScreenshot(page, '03-after-login');
    
    // Check if login was successful
    // If login succeeds, we should NOT see the login form anymore
    const stillOnLoginPage = await passwordField.isVisible().catch(() => false);
    
    if (stillOnLoginPage) {
      // Check for error messages
      const pageContent = await page.content();
      console.log('Still on login page. Page content:', pageContent.substring(0, 500));
      
      // This would indicate a login failure
      expect(stillOnLoginPage).toBe(false);
    }
    
    // Verify we're logged in - look for LuCI interface elements
    // After successful login, we should see navigation or the main interface
    const currentUrl = page.url();
    console.log('Current URL after login:', currentUrl);
    
    // The URL should change from the login page
    expect(currentUrl).not.toContain('sysauth');
    
    console.log('✅ Test passed: Login succeeded with just password when key is empty');
  });
  
  test('should show OTP field when 2FA enabled with a valid key', async ({ page }) => {
    console.log('Test: 2FA enabled with valid key - OTP field should appear');
    
    // Set 2FA enabled with a valid key
    const testKey = 'JBSWY3DPEHPK3PXP'; // Valid base32 key
    await set2FAConfig(true, testKey);
    
    // Navigate to login page
    await page.goto('http://localhost:8080/cgi-bin/luci/', { 
      waitUntil: 'domcontentloaded', 
      timeout: 30000 
    });
    
    await takeScreenshot(page, '04-login-with-key');
    
    // Verify OTP field IS visible when key is configured
    const otpField = page.locator('input[name="luci_otp"], #luci_otp');
    await expect(otpField).toBeVisible({ timeout: 10000 });
    
    console.log('✅ Test passed: OTP field appears when key is configured');
  });
  
  test.afterAll(async () => {
    // Cleanup: Reset to default state (disabled)
    console.log('Cleaning up test environment...');
    await set2FAConfig(false, '');
  });
});
