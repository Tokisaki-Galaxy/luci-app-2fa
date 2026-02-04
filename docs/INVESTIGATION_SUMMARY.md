# 2FA Plugin Behavior Investigation - Summary

## Investigation Request

The user asked two questions about the 2FA plugin behavior:

1. **Question 1 (Chinese)**: 如果这个插件启用的时候,密钥设置为空,登录界面会怎么样?会不会无法登录
   - **English**: If the plugin is enabled but the key is empty, what happens at login? Will users be unable to log in?

2. **Question 2 (Chinese)**: 如果root启用,但是切换到另一个用户登录,他们两个是共享一个TOTP密钥吗?
   - **English**: If root has 2FA enabled but you switch to another user, do they share the same TOTP key?

## Answers

### Question 1: Empty Key Behavior

**Answer**: ✅ **Users CAN still log in with just their password** (2FA is automatically bypassed)

- When 2FA is globally enabled but a user's key is empty
- The system automatically bypasses 2FA for that user
- Login proceeds normally with just username and password
- No OTP field is shown on the login page
- This is a **safety feature** to prevent lockout scenarios

### Question 2: User-Specific Keys

**Answer**: ✅ **Each user has their own separate TOTP key** (keys are NOT shared)

- Each user has their own UCI configuration section
- Keys are stored per-user: `2fa.root.key`, `2fa.admin.key`, etc.
- Different users can have different keys, types (TOTP/HOTP), and settings
- Users are completely independent in their 2FA configuration

## Deliverables

### 1. Documentation

- **[docs/检查结果.md](./docs/检查结果.md)**: Complete answers in Chinese
- **[docs/BEHAVIOR_ANALYSIS.md](./docs/BEHAVIOR_ANALYSIS.md)**: Detailed technical analysis in English

### 2. Test Suite

Created comprehensive E2E tests to verify both behaviors:

- **[tests/e2e/empty-key-behavior.spec.ts](./tests/e2e/empty-key-behavior.spec.ts)**
  - Tests login with 2FA enabled but empty key
  - Verifies OTP field is NOT shown
  - Confirms password-only login succeeds

- **[tests/e2e/user-specific-keys.spec.ts](./tests/e2e/user-specific-keys.spec.ts)**
  - Tests multiple users with different keys
  - Verifies UCI config structure for user separation
  - Confirms keys are stored independently
  - Tests `isEnabled` RPC call for user-specific behavior

### 3. Code Analysis

Analyzed the authentication flow:

1. **`luci-app-2fa/root/usr/share/luci/auth.d/2fa.uc`** (lines 356-377)
   - `is_2fa_enabled()` function checks if user has a key
   - Returns `false` if key is empty → 2FA bypassed

2. **`luci-app-2fa/root/etc/config/2fa`** (lines 13-17)
   - Shows UCI config structure with user-specific sections
   - Each user: `config login 'username'`

3. **`luci-app-2fa/root/usr/share/rpcd/ucode/2fa.uc`** (line 402)
   - Key retrieval: `ctx.get('2fa', safe_username, 'key')`
   - Username is the UCI section name

## Key Findings

### Empty Key is Safe

The empty key bypass is **intentional and safe**:

- ✅ User still needs valid password to log in
- ✅ Prevents lockout if 2FA is misconfigured
- ✅ Admin can log in to fix/configure 2FA
- ✅ No security compromise (password auth still required)

### User Isolation is Proper

Having separate keys per user provides:

- ✅ Individual accountability
- ✅ Security isolation (compromising one user doesn't affect others)
- ✅ Flexible deployment (gradual rollout per user)
- ✅ Easy key rotation (per-user basis)

## Conclusion

**Both behaviors are working correctly as designed. No code changes are needed.**

The plugin implements:

1. ✅ Safe empty-key handling (automatic bypass)
2. ✅ Proper user isolation (separate keys per user)

Both features provide good security with user-friendly safety mechanisms.

## Running the Tests

To verify these behaviors:

```bash
# Install dependencies
npm install

# Run all tests
npm test

# Run E2E tests specifically
npm run test:e2e

# Run just the new tests
npx playwright test tests/e2e/empty-key-behavior.spec.ts
npx playwright test tests/e2e/user-specific-keys.spec.ts
```

## Documentation Files

- **Chinese Summary**: [docs/检查结果.md](./docs/检查结果.md)
- **English Analysis**: [docs/BEHAVIOR_ANALYSIS.md](./docs/BEHAVIOR_ANALYSIS.md)
- **This Summary**: [docs/INVESTIGATION_SUMMARY.md](./docs/INVESTIGATION_SUMMARY.md)

## Security Recommendations

### For Administrators:

1. Enable 2FA gradually (test with your own account first)
2. Keep a backup admin account without 2FA
3. Use IP whitelisting for trusted LAN networks
4. Document recovery procedures

### For Users:

1. Generate and save your key immediately after enabling 2FA
2. Test login with OTP before logging out
3. Save backup codes or QR code securely
4. Each user needs their own authenticator app entry

---

**Investigation completed successfully. All questions answered with code evidence and tests.**
