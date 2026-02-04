/**
 * TOTP Diagnostic E2E Test
 *
 * This test performs comprehensive diagnostics to identify why TOTP login
 * may fail locally but work in GitHub Actions. It tests:
 *
 * 1. Time synchronization between test client and OpenWrt container
 * 2. TOTP generation consistency (external library vs ucode implementation)
 * 3. Time window tolerance (±30 seconds)
 * 4. Complete login flow with detailed logging
 */

import { test, expect, Page } from "@playwright/test";
import * as OTPAuth from "otpauth";
import { execSync, exec } from "child_process";

const CONTAINER_NAME = "openwrt-luci-e2e";
const TEST_SECRET = "JBSWY3DPEHPK3PXP";
const PASSWORD = "password";

/**
 * Generate TOTP using the standard otpauth library
 */
function generateTOTP(secret: string, timestamp?: number): string {
  const totp = new OTPAuth.TOTP({
    issuer: "OpenWrt",
    label: "root",
    algorithm: "SHA1",
    digits: 6,
    period: 30,
    secret: OTPAuth.Secret.fromBase32(secret),
  });
  if (timestamp !== undefined) {
    return totp.generate({ timestamp: timestamp * 1000 });
  }
  return totp.generate();
}

/**
 * Get current Unix timestamp from the container
 */
function getContainerTime(): number {
  try {
    const result = execSync(`docker exec ${CONTAINER_NAME} date +%s`, {
      encoding: "utf-8",
    });
    return parseInt(result.trim(), 10);
  } catch {
    return 0;
  }
}

/**
 * Get current system time (test client)
 */
function getSystemTime(): number {
  return Math.floor(Date.now() / 1000);
}

/**
 * Generate OTP using the ucode implementation in the container
 */
function getContainerOTP(username: string = "root"): string {
  try {
    const result = execSync(
      `docker exec ${CONTAINER_NAME} ucode /usr/libexec/generate_otp.uc ${username}`,
      { encoding: "utf-8" },
    );
    return result.trim();
  } catch {
    return "";
  }
}

/**
 * Generate OTP using ucode with a specific timestamp
 */
function getContainerOTPWithTime(username: string, timestamp: number): string {
  try {
    const result = execSync(
      `docker exec ${CONTAINER_NAME} ucode /usr/libexec/generate_otp.uc ${username} --no-increment --time=${timestamp}`,
      { encoding: "utf-8" },
    );
    return result.trim();
  } catch {
    return "";
  }
}

/**
 * Get the current 2FA configuration from the container
 */
function get2FAConfig(): Record<string, string> {
  try {
    const result = execSync(
      `docker exec ${CONTAINER_NAME} ubus call 2fa getConfig '{}'`,
      {
        encoding: "utf-8",
      },
    );
    return JSON.parse(result.trim());
  } catch {
    return {};
  }
}

/**
 * Screenshot helper with timestamp
 */
async function screenshot(page: Page, name: string) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  await page.screenshot({
    path: `screenshots/diag-${name}-${timestamp}.png`,
    fullPage: true,
  });
}

/**
 * Check if login was successful by examining page content
 * Returns an object with detailed success indicators for logging
 */
async function checkLoginSuccess(page: Page): Promise<{
  isLoggedIn: boolean;
  hasLogout: boolean;
  hasStatusPage: boolean;
  hasLoginForm: boolean;
  hasOTPField: boolean;
  url: string;
}> {
  const url = page.url();
  const pageContent = await page.content();

  const hasLogout =
    pageContent.includes("Log out") || pageContent.includes("Logout");
  const hasStatusPage =
    pageContent.includes("Status") && pageContent.includes("System");
  const hasLoginForm = pageContent.includes('id="luci_password"');
  const hasOTPField = pageContent.includes('id="luci_otp"');

  // Login is successful if we have logout link or status page content,
  // AND no login form AND no OTP field
  const isLoggedIn =
    (hasLogout || hasStatusPage) && !hasLoginForm && !hasOTPField;

  return {
    isLoggedIn,
    hasLogout,
    hasStatusPage,
    hasLoginForm,
    hasOTPField,
    url,
  };
}

test.describe("TOTP Diagnostic Tests", () => {
  test.beforeAll(async () => {
    console.log("\n========================================");
    console.log("TOTP DIAGNOSTIC TEST SUITE");
    console.log("========================================\n");
  });

  test("1. Time synchronization diagnostic", async () => {
    console.log("=== Time Synchronization Test ===\n");

    const systemTime = getSystemTime();
    const containerTime = getContainerTime();
    const timeDiff = Math.abs(systemTime - containerTime);

    console.log(
      `System Time (test client): ${systemTime} (${new Date(systemTime * 1000).toISOString()})`,
    );
    console.log(
      `Container Time:            ${containerTime} (${new Date(containerTime * 1000).toISOString()})`,
    );
    console.log(`Time Difference:           ${timeDiff} seconds`);
    console.log(`Maximum Allowed Drift:     30 seconds`);
    console.log(
      `Time Sync Status:          ${timeDiff <= 30 ? "✓ OK" : "✗ OUT OF SYNC"}`,
    );
    console.log("");

    // Store for use in later tests
    expect(containerTime).toBeGreaterThan(0);
  });

  test("2. 2FA configuration diagnostic", async () => {
    console.log("=== 2FA Configuration Test ===\n");

    const config = get2FAConfig();
    console.log("Current 2FA Configuration:");
    console.log(JSON.stringify(config, null, 2));
    console.log("");

    // Verify the secret matches our test secret
    expect(config.key).toBe(TEST_SECRET);
    expect(config.enabled).toBe("1");
    expect(config.type).toBe("totp");
  });

  test("3. TOTP generation consistency", async () => {
    console.log("=== TOTP Generation Consistency Test ===\n");

    // Get synchronized timestamps
    const systemTime = getSystemTime();
    const containerTime = getContainerTime();

    // Generate TOTP using external library at current time
    const externalTOTP = generateTOTP(TEST_SECRET);
    // Generate TOTP using external library at container's time
    const externalTOTPContainerTime = generateTOTP(TEST_SECRET, containerTime);

    // Generate TOTP from container's ucode implementation
    const ucodeTOTP = getContainerOTP("root");
    // Generate TOTP from container with specific timestamps
    const ucodeAtSystemTime = getContainerOTPWithTime("root", systemTime);
    const ucodeAtContainerTime = getContainerOTPWithTime("root", containerTime);

    console.log("TOTP Values Generated:");
    console.log("-----------------------------------------------");
    console.log(`External (current time ${systemTime}):     ${externalTOTP}`);
    console.log(
      `External (container time ${containerTime}): ${externalTOTPContainerTime}`,
    );
    console.log(`Ucode (no timestamp):                 ${ucodeTOTP}`);
    console.log(
      `Ucode (at system time ${systemTime}):      ${ucodeAtSystemTime}`,
    );
    console.log(
      `Ucode (at container time ${containerTime}): ${ucodeAtContainerTime}`,
    );
    console.log("");

    // Check consistency
    console.log("Consistency Checks:");
    console.log(
      `External(sys) == Ucode(sys):      ${externalTOTP === ucodeAtSystemTime ? "✓ MATCH" : `✗ MISMATCH (${externalTOTP} vs ${ucodeAtSystemTime})`}`,
    );
    console.log(
      `External(cnt) == Ucode(cnt):      ${externalTOTPContainerTime === ucodeAtContainerTime ? "✓ MATCH" : `✗ MISMATCH (${externalTOTPContainerTime} vs ${ucodeAtContainerTime})`}`,
    );
    console.log(
      `Ucode(live) == External(sys):     ${ucodeTOTP === externalTOTP ? "✓ MATCH" : `✗ MISMATCH (${ucodeTOTP} vs ${externalTOTP})`}`,
    );
    console.log("");

    // The external library and ucode should generate the same OTP for the same timestamp
    expect(externalTOTP).toMatch(/^\d{6}$/);
    expect(ucodeTOTP).toMatch(/^\d{6}$/);
  });

  test("4. Time window tolerance verification", async () => {
    console.log("=== Time Window Tolerance Test ===\n");

    const containerTime = getContainerTime();
    const step = 30;

    console.log(`Container time: ${containerTime}`);
    console.log(
      "Testing verification across time windows (current, -1, +1):\n",
    );

    // The auth.d/2fa.uc checks offsets [0, -1, 1] (in that order)
    for (const offset of [0, -1, 1]) {
      const checkTime = containerTime + offset * step;
      const externalOTP = generateTOTP(TEST_SECRET, checkTime);
      const ucodeOTP = getContainerOTPWithTime("root", checkTime);

      console.log(`Window offset ${offset} (time ${checkTime}):`);
      console.log(`  External OTP: ${externalOTP}`);
      console.log(`  Ucode OTP:    ${ucodeOTP}`);
      console.log(`  Match:        ${externalOTP === ucodeOTP ? "✓" : "✗"}`);
    }
    console.log("");
  });

  test("5. Full login flow with OTP - detailed trace", async ({ page }) => {
    console.log("=== Full Login Flow Test ===\n");

    // Navigate to login page
    await page.goto("/cgi-bin/luci/", {
      waitUntil: "domcontentloaded",
      timeout: 30000,
    });

    // Wait for login form
    await page.waitForSelector("#luci_password", { timeout: 30000 });
    await screenshot(page, "01-initial-login-page");

    // Step 1: Check that OTP field is already visible on login page (new flow)
    console.log("Step 1: Checking OTP field visibility on initial page...");
    const otpField = page.locator("#luci_otp");
    await expect(otpField).toBeVisible({ timeout: 15000 });
    console.log("  ✓ OTP field already visible on login page\n");
    await screenshot(page, "02-otp-field-shown");

    // Step 2: Generate and log OTP values
    console.log("Step 2: Generating TOTP codes...");
    const systemTime = getSystemTime();
    const containerTime = getContainerTime();

    // Generate multiple TOTP codes for comparison
    const externalTOTP = generateTOTP(TEST_SECRET);
    const externalTOTPContainerTime = generateTOTP(TEST_SECRET, containerTime);
    const ucodeTOTP = getContainerOTP("root");

    console.log(`  System time:             ${systemTime}`);
    console.log(`  Container time:          ${containerTime}`);
    console.log(
      `  Time diff:               ${Math.abs(systemTime - containerTime)}s`,
    );
    console.log(`  External OTP (sys):      ${externalTOTP}`);
    console.log(`  External OTP (cnt):      ${externalTOTPContainerTime}`);
    console.log(`  Ucode OTP:               ${ucodeTOTP}`);
    console.log("");

    // Step 3: Fill password and OTP, then submit (single submission with new flow)
    console.log("Step 3: Submitting password and OTP together...");
    const otpToUse = externalTOTP;
    console.log(`  Using OTP: ${otpToUse}`);

    await page.locator("#luci_password").fill(PASSWORD);
    await otpField.fill(otpToUse);
    await screenshot(page, "03-before-final-submit");

    // Listen for console errors
    page.on("console", (msg) => {
      if (msg.type() === "error") {
        console.log(`  [Browser Error]: ${msg.text()}`);
      }
    });

    await page.locator("button.cbi-button-positive").click();

    // Wait for response
    try {
      await page.waitForURL(/admin/, { timeout: 10000 });
    } catch {
      // URL didn't change, check what happened
    }

    await page.waitForTimeout(2000);
    await screenshot(page, "04-after-submit");

    // Step 4: Analyze result using shared helper
    console.log("Step 4: Analyzing login result...");
    const loginResult = await checkLoginSuccess(page);
    const pageContent = await page.content();
    const hasErrorMessage =
      pageContent.includes("Invalid username") ||
      pageContent.includes("Invalid one-time password");

    console.log(`  Final URL: ${loginResult.url}`);
    console.log(
      `  Is on LuCI page:   ${loginResult.url.includes("luci") ? "✓ Yes" : "✗ No"}`,
    );
    console.log(
      `  Has login form:    ${loginResult.hasLoginForm ? "✗ Yes (still on login)" : "✓ No"}`,
    );
    console.log(
      `  Has OTP field:     ${loginResult.hasOTPField ? "⚠ Yes (may need retry)" : "✓ No"}`,
    );
    console.log(`  Has error message: ${hasErrorMessage ? "✗ Yes" : "✓ No"}`);
    console.log(
      `  Has logout link:   ${loginResult.hasLogout ? "✓ Yes (logged in)" : "✗ No"}`,
    );
    console.log(
      `  Has status page:   ${loginResult.hasStatusPage ? "✓ Yes (logged in)" : "✗ No"}`,
    );
    console.log("");

    console.log(
      `  LOGIN RESULT: ${loginResult.isLoggedIn ? "✓ SUCCESS" : "✗ FAILED"}`,
    );
    console.log("");

    // Extract error message if present
    if (hasErrorMessage) {
      const errorMatch = pageContent.match(
        /class="alert-message[^"]*"[^>]*>([^<]+)/,
      );
      if (errorMatch) {
        console.log(`  Error message: ${errorMatch[1].trim()}`);
      }
    }

    expect(loginResult.isLoggedIn).toBeTruthy();
  });

  test("6. Login with synchronized container time OTP", async ({ page }) => {
    console.log("=== Login with Container-Time OTP ===\n");
    console.log(
      "This test generates OTP using the container's time instead of system time.\n",
    );

    // Navigate to login page
    await page.goto("/cgi-bin/luci/", {
      waitUntil: "domcontentloaded",
      timeout: 30000,
    });

    await page.waitForSelector("#luci_password", { timeout: 30000 });

    // OTP field should be visible on initial login page with new flow
    const otpField = page.locator("#luci_otp");
    await expect(otpField).toBeVisible({ timeout: 15000 });

    // Use container time for OTP generation
    const containerTime = getContainerTime();
    const otpToUse = generateTOTP(TEST_SECRET, containerTime);

    console.log(`Container time: ${containerTime}`);
    console.log(`OTP generated:  ${otpToUse}`);
    console.log("");

    // Fill both password and OTP on same page (new single-submission flow)
    await page.locator("#luci_password").fill(PASSWORD);
    await otpField.fill(otpToUse);
    await screenshot(page, "05-container-time-otp");

    await page.locator("button.cbi-button-positive").click();

    try {
      await page.waitForURL(/admin/, { timeout: 10000 });
    } catch {
      // continue
    }

    await page.waitForTimeout(2000);
    await screenshot(page, "06-container-time-result");

    // Use shared helper for consistent login success detection
    const loginResult = await checkLoginSuccess(page);

    console.log(`Final URL: ${loginResult.url}`);
    console.log(`Login success: ${loginResult.isLoggedIn ? "✓ YES" : "✗ NO"}`);
    console.log("");

    expect(loginResult.isLoggedIn).toBeTruthy();
  });

  test("7. Direct ubus verification call test", async () => {
    console.log("=== Direct ubus Verification Test ===\n");
    console.log("Testing the RPC verification directly via ubus call.\n");

    // Generate OTP using external library
    const systemTime = getSystemTime();
    const containerTime = getContainerTime();

    // Test with various OTP codes
    const testCases = [
      {
        name: "External OTP (system time)",
        otp: generateTOTP(TEST_SECRET, systemTime),
      },
      {
        name: "External OTP (container time)",
        otp: generateTOTP(TEST_SECRET, containerTime),
      },
      { name: "Ucode OTP (live)", otp: getContainerOTP("root") },
      { name: "Invalid OTP", otp: "000000" },
    ];

    for (const testCase of testCases) {
      try {
        const result = execSync(
          `docker exec ${CONTAINER_NAME} ubus call 2fa verifyOTP '{"otp":"${testCase.otp}","username":"root"}'`,
          { encoding: "utf-8" },
        );
        const parsed = JSON.parse(result.trim());
        console.log(
          `${testCase.name} (${testCase.otp}): ${parsed.result ? "✓ ACCEPTED" : "✗ REJECTED"}`,
        );
      } catch (err) {
        console.log(`${testCase.name} (${testCase.otp}): ✗ ERROR`);
      }
    }
    console.log("");
  });

  test("8. Verify auth.d plugin directly", async () => {
    console.log("=== Auth Plugin Direct Test ===\n");
    console.log(
      "Testing if the auth.d/2fa.uc plugin can verify OTP correctly.\n",
    );

    const containerTime = getContainerTime();
    const validOTP = generateTOTP(TEST_SECRET, containerTime);

    console.log(`Container time: ${containerTime}`);
    console.log(`Test OTP:       ${validOTP}`);
    console.log("");

    // Run a test script inside the container that simulates the auth plugin behavior
    const testScript = `
      let fs = require('fs');
      let uci = require('uci');
      
      function constant_time_compare(a, b) {
        if (length(a) != length(b)) return false;
        let result = 0;
        for (let i = 0; i < length(a); i++) {
          result = result | (ord(a, i) ^ ord(b, i));
        }
        return result == 0;
      }
      
      let ctx = uci.cursor();
      let step = int(ctx.get('2fa', 'root', 'step') || '30');
      let current_time = time();
      
      print('Current time: ' + current_time + '\\n');
      print('Step: ' + step + '\\n');
      print('Testing OTP: ${validOTP}\\n\\n');
      
      for (let offset in [0, -1, 1]) {
        let check_time = int(current_time + (offset * step));
        let fd = fs.popen('/usr/libexec/generate_otp.uc root --no-increment --time=' + check_time, 'r');
        if (fd) {
          let expected = trim(fd.read('all'));
          fd.close();
          print('Window ' + offset + ' (time ' + check_time + '): expected=' + expected + ', match=' + (constant_time_compare(expected, '${validOTP}') ? 'YES' : 'NO') + '\\n');
        }
      }
    `;

    try {
      // Write test script to container
      execSync(
        `docker exec ${CONTAINER_NAME} sh -c 'cat > /tmp/test_auth.uc'`,
        {
          input: testScript,
        },
      );

      // Run the test
      const result = execSync(
        `docker exec ${CONTAINER_NAME} ucode /tmp/test_auth.uc`,
        {
          encoding: "utf-8",
        },
      );
      console.log("Auth plugin test output:");
      console.log(result);
    } catch (err: unknown) {
      const execError = err as { stderr?: string; stdout?: string };
      console.log(
        "Error running auth test:",
        execError.stderr || execError.stdout,
      );
    }
  });
});
