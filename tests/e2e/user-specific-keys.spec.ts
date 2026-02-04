/**
 * User-Specific Keys Test
 *
 * This test verifies that different users have separate TOTP keys and do NOT share keys.
 *
 * Expected Behavior (based on code analysis):
 * - Each user has their own UCI section: config login 'username'
 * - Each user's key is stored separately under their own section
 * - Root user's key: ctx.get('2fa', 'root', 'key')
 * - Other user's key: ctx.get('2fa', 'username', 'key')
 * - Users do NOT share TOTP keys
 *
 * This test answers Question 2: "If root has 2FA enabled, do other users
 * share the same TOTP key?"
 *
 * Answer: NO - each user has their own separate TOTP key stored in their own UCI section.
 */

import { test, expect } from "@playwright/test";

/**
 * Helper: Execute UCI commands in the OpenWrt container
 */
async function execUCI(command: string): Promise<string> {
  const { exec } = await import("child_process");
  const { promisify } = await import("util");
  const execAsync = promisify(exec);

  try {
    const { stdout, stderr } = await execAsync(
      `docker exec openwrt-luci sh -c "${command}"`,
    );
    if (stderr && !stderr.includes("Warning")) {
      console.error("UCI stderr:", stderr);
    }
    return stdout.trim();
  } catch (error: any) {
    // For non-existent keys, uci get returns exit code 1
    if (error.message.includes("Entry not found")) {
      return "";
    }
    console.error("UCI command failed:", error.message);
    throw error;
  }
}

/**
 * Helper: Set up a user's 2FA configuration
 */
async function setupUser2FA(
  username: string,
  key: string,
  type: string = "totp",
): Promise<void> {
  // Create the user section if it doesn't exist
  await execUCI(`uci set 2fa.${username}=login`);
  await execUCI(`uci set 2fa.${username}.key='${key}'`);
  await execUCI(`uci set 2fa.${username}.type='${type}'`);
  await execUCI(`uci set 2fa.${username}.step='30'`);
  await execUCI(`uci set 2fa.${username}.counter='0'`);
  await execUCI("uci commit 2fa");
}

/**
 * Helper: Get a user's key from UCI
 */
async function getUserKey(username: string): Promise<string> {
  return await execUCI(`uci get 2fa.${username}.key`);
}

/**
 * Helper: Delete a user's 2FA configuration
 */
async function deleteUser2FA(username: string): Promise<void> {
  await execUCI(`uci delete 2fa.${username} 2>/dev/null || true`);
  await execUCI("uci commit 2fa");
}

test.describe("User-Specific Keys - Question 2", () => {
  // Different keys for different users
  const ROOT_KEY = "JBSWY3DPEHPK3PXP"; // "Hello!" in base32
  const ADMIN_KEY = "GEZDGNBVGY3TQOJQ"; // Different key
  const USER1_KEY = "MFRGGZDFMZTWQ2LK"; // Another different key

  test.beforeAll(async () => {
    console.log("Setting up test users...");

    // Enable 2FA globally
    await execUCI("uci set 2fa.settings.enabled='1'");
    await execUCI("uci commit 2fa");
  });

  test("should store separate keys for different users", async () => {
    console.log("Test: Each user should have their own separate TOTP key");

    // Set up different keys for different users
    await setupUser2FA("root", ROOT_KEY);
    await setupUser2FA("admin", ADMIN_KEY);
    await setupUser2FA("user1", USER1_KEY);

    // Wait a moment for changes to be persisted
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Retrieve keys for each user
    const retrievedRootKey = await getUserKey("root");
    const retrievedAdminKey = await getUserKey("admin");
    const retrievedUser1Key = await getUserKey("user1");

    console.log("Root key:", retrievedRootKey);
    console.log("Admin key:", retrievedAdminKey);
    console.log("User1 key:", retrievedUser1Key);

    // Verify each user has their own key
    expect(retrievedRootKey).toBe(ROOT_KEY);
    expect(retrievedAdminKey).toBe(ADMIN_KEY);
    expect(retrievedUser1Key).toBe(USER1_KEY);

    // Verify keys are different from each other
    expect(retrievedRootKey).not.toBe(retrievedAdminKey);
    expect(retrievedRootKey).not.toBe(retrievedUser1Key);
    expect(retrievedAdminKey).not.toBe(retrievedUser1Key);

    console.log("✅ Test passed: Each user has their own separate key");
  });

  test("should verify UCI config structure for multiple users", async () => {
    console.log("Test: Verify UCI config has separate sections for each user");

    // Get the entire 2fa config
    const config = await execUCI("uci show 2fa");
    console.log("Full 2FA configuration:");
    console.log(config);

    // Verify each user has their own section
    expect(config).toContain("2fa.root=login");
    expect(config).toContain("2fa.admin=login");
    expect(config).toContain("2fa.user1=login");

    // Verify each user has their own key
    expect(config).toContain(`2fa.root.key='${ROOT_KEY}'`);
    expect(config).toContain(`2fa.admin.key='${ADMIN_KEY}'`);
    expect(config).toContain(`2fa.user1.key='${USER1_KEY}'`);

    console.log(
      "✅ Test passed: UCI config has separate sections for each user",
    );
  });

  test("should allow one user to have 2FA enabled while another has empty key", async () => {
    console.log(
      "Test: One user with key, another without - independent configuration",
    );

    // Set root with a key
    await setupUser2FA("root", ROOT_KEY);

    // Set admin with empty key (2FA disabled for this user)
    await setupUser2FA("admin", "");

    // Retrieve keys
    const rootKey = await getUserKey("root");
    const adminKey = await getUserKey("admin");

    console.log("Root key (should have value):", rootKey);
    console.log("Admin key (should be empty):", adminKey);

    // Verify root has a key but admin doesn't
    expect(rootKey).toBe(ROOT_KEY);
    expect(adminKey).toBe("");

    console.log(
      "✅ Test passed: Users can have independent 2FA configurations",
    );
  });

  test("should verify is_2fa_enabled logic checks user-specific key", async () => {
    console.log("Test: Verify is_2fa_enabled() uses user-specific keys");

    // Set up scenario:
    // - Global 2FA enabled
    // - Root has a key (2FA active for root)
    // - Admin has no key (2FA bypassed for admin)

    await execUCI("uci set 2fa.settings.enabled='1'");
    await setupUser2FA("root", ROOT_KEY);
    await setupUser2FA("admin", ""); // Empty key
    await execUCI("uci commit 2fa");

    // Restart rpcd to reload config
    await execUCI("kill -9 $(pgrep rpcd) 2>/dev/null || true");
    await execUCI("/sbin/rpcd &");
    await new Promise((resolve) => setTimeout(resolve, 2000));

    // Call the isEnabled RPC method for each user
    const rootEnabled = await execUCI(
      'ubus call 2fa isEnabled \'{"username":"root"}\' 2>/dev/null',
    );
    const adminEnabled = await execUCI(
      'ubus call 2fa isEnabled \'{"username":"admin"}\' 2>/dev/null',
    );

    console.log("Root isEnabled response:", rootEnabled);
    console.log("Admin isEnabled response:", adminEnabled);

    // Parse JSON responses
    const rootResult = JSON.parse(rootEnabled);
    const adminResult = JSON.parse(adminEnabled);

    // Verify: root should have 2FA enabled, admin should not
    expect(rootResult.enabled).toBe(true); // Root has a key
    expect(adminResult.enabled).toBe(false); // Admin has no key

    console.log(
      "✅ Test passed: is_2fa_enabled() correctly checks user-specific keys",
    );
  });

  test.afterAll(async () => {
    console.log("Cleaning up test users...");

    // Clean up test users
    await deleteUser2FA("admin");
    await deleteUser2FA("user1");

    // Reset root to empty key
    await setupUser2FA("root", "");

    // Disable 2FA globally
    await execUCI("uci set 2fa.settings.enabled='0'");
    await execUCI("uci commit 2fa");

    // Restart rpcd
    await execUCI("kill -9 $(pgrep rpcd) 2>/dev/null || true");
    await execUCI("/sbin/rpcd &");
  });
});
