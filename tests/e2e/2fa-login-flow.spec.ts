/**
 * 2FA Login Flow E2E Test
 *
 * Tests the complete login flow with 2FA enabled using Playwright and the standard TOTP library.
 * This test validates that:
 * 1. Password authentication shows the OTP field
 * 2. Correct TOTP code allows login
 * 3. Incorrect TOTP code is rejected
 */

import { test, expect, Page } from "@playwright/test";
import * as OTPAuth from "otpauth";

// Test configuration - should match the 2FA setup in the container
const TEST_SECRET = "JBSWY3DPEHPK3PXP";
const PASSWORD = "password";

/**
 * Generate a valid TOTP code using the standard otpauth library
 */
function generateTOTP(secret: string): string {
  const totp = new OTPAuth.TOTP({
    issuer: "OpenWrt",
    label: "root",
    algorithm: "SHA1",
    digits: 6,
    period: 30,
    secret: OTPAuth.Secret.fromBase32(secret),
  });
  return totp.generate();
}

/**
 * Helper function to take screenshots with descriptive names
 */
async function takeScreenshot(page: Page, name: string) {
  await page.screenshot({
    path: `screenshots/2fa-${name}.png`,
    fullPage: true,
  });
}

/**
 * Wait for page to be ready after navigation or form submission
 */
async function waitForPageReady(page: Page) {
  try {
    await page.waitForLoadState("domcontentloaded", { timeout: 30000 });
  } catch (error) {
    console.log("Warning: Page load state timeout, continuing anyway...");
  }
}

test.describe("2FA Login Flow", () => {
  test("should show OTP field on initial login page when 2FA is enabled", async ({
    page,
  }) => {
    // Navigate to login page
    await page.goto("/cgi-bin/luci/", {
      waitUntil: "domcontentloaded",
      timeout: 30000,
    });
    await waitForPageReady(page);

    // Take screenshot of initial login page
    await takeScreenshot(page, "01-login-page");

    // Verify password field is visible
    const passwordField = page.locator("#luci_password");
    await expect(passwordField).toBeVisible({ timeout: 10000 });

    // Verify OTP field is already visible on the initial login page (new flow)
    const otpField = page.locator("#luci_otp");
    await expect(otpField).toBeVisible({ timeout: 10000 });

    // Verify the message about OTP
    const pageContent = await page.content();
    expect(pageContent).toContain("One-Time Password");
  });

  test("should successfully login with correct TOTP code", async ({ page }) => {
    // Navigate to login page
    await page.goto("/cgi-bin/luci/", {
      waitUntil: "domcontentloaded",
      timeout: 30000,
    });
    await waitForPageReady(page);

    // Fill in password
    const passwordField = page.locator("#luci_password");
    await expect(passwordField).toBeVisible({ timeout: 10000 });
    await passwordField.fill(PASSWORD);

    // OTP field should be visible on initial login page with new flow
    const otpField = page.locator("#luci_otp");
    await expect(otpField).toBeVisible({ timeout: 10000 });

    // Generate TOTP code
    const otpCode = generateTOTP(TEST_SECRET);
    console.log("Generated TOTP code:", otpCode);

    // Fill in OTP field
    await otpField.fill(otpCode);

    // Take screenshot before submit
    await takeScreenshot(page, "03-before-2fa-submit");

    // Submit login
    const loginButton = page.locator("button.cbi-button-positive");
    await loginButton.click();

    // Wait for redirect
    await waitForPageReady(page);

    // Take screenshot after login
    await takeScreenshot(page, "04-after-2fa-login");

    // Verify we are logged in - should be on admin page or have session
    const currentUrl = page.url();
    console.log("Current URL after login:", currentUrl);

    // The page should either redirect to admin or show the admin content
    // Check for sessionid in the page content which indicates successful login
    const pageContent = await page.content();
    const hasSession =
      pageContent.includes("sessionid") &&
      !pageContent.includes('"sessionid": null');
    const isOnAdminPage = currentUrl.includes("admin");
    const hasLogoutOption =
      pageContent.includes("Logout") || pageContent.includes("logout");

    expect(hasSession || isOnAdminPage || hasLogoutOption).toBeTruthy();
  });

  test("should reject incorrect TOTP code", async ({ page }) => {
    // Navigate to login page
    await page.goto("/cgi-bin/luci/", {
      waitUntil: "domcontentloaded",
      timeout: 30000,
    });
    await waitForPageReady(page);

    // Fill in password
    const passwordField = page.locator("#luci_password");
    await expect(passwordField).toBeVisible({ timeout: 10000 });
    await passwordField.fill(PASSWORD);

    // OTP field should be visible on initial login page with new flow
    const otpField = page.locator("#luci_otp");
    await expect(otpField).toBeVisible({ timeout: 10000 });

    // Fill in incorrect OTP
    await otpField.fill("000000"); // Wrong code

    // Take screenshot
    await takeScreenshot(page, "05-wrong-otp");

    // Submit
    const loginButton = page.locator("button.cbi-button-positive");
    await loginButton.click();

    // Wait for response
    await waitForPageReady(page);

    // Take screenshot of error
    await takeScreenshot(page, "06-wrong-otp-error");

    // Should show error message and stay on login page
    const pageContent = await page.content();
    const hasError =
      pageContent.includes("Invalid") ||
      pageContent.includes("invalid") ||
      pageContent.includes("error");
    const stillOnLoginPage =
      pageContent.includes("luci_otp") || pageContent.includes("luci_password");

    expect(hasError || stillOnLoginPage).toBeTruthy();
  });

  test("should verify TOTP matches standard implementation", async ({
    page,
  }) => {
    // This test verifies that the TOTP codes generated by both
    // the ucode implementation and the standard library match

    // Navigate to login page
    await page.goto("/cgi-bin/luci/", {
      waitUntil: "domcontentloaded",
      timeout: 30000,
    });
    await waitForPageReady(page);

    // Generate TOTP with standard library
    const standardTOTP = generateTOTP(TEST_SECRET);
    console.log("Standard TOTP library generated:", standardTOTP);

    // The test environment should have the same secret configured
    // and generate the same code (verified via curl in setup)
    expect(standardTOTP).toMatch(/^\d{6}$/);

    // Fill in credentials - both password and OTP on same page with new flow
    await page.locator("#luci_password").fill(PASSWORD);

    // OTP field should be visible on initial login page
    const otpField = page.locator("#luci_otp");
    await expect(otpField).toBeVisible({ timeout: 10000 });
    await otpField.fill(standardTOTP);

    await page.locator("button.cbi-button-positive").click();
    await waitForPageReady(page);

    // Take final screenshot
    await takeScreenshot(page, "07-standard-totp-result");

    // Verify login succeeded
    const pageContent = await page.content();
    const loginSucceeded =
      pageContent.includes("sessionid") &&
      !pageContent.includes('"sessionid": null');

    expect(loginSucceeded).toBeTruthy();
  });
});
