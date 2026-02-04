# 2FA Plugin Behavior Investigation - Documentation Index

This directory contains the complete investigation results for two questions about the 2FA plugin behavior.

## Questions Investigated

1. **问题 1 / Question 1**: If the plugin is enabled but the secret key is empty, what happens at login? Will users be unable to log in?

2. **问题 2 / Question 2**: If root has 2FA enabled but you switch to another user to log in, do they share the same TOTP key?

## Documentation Files

### For Quick Answers / 快速查看

📋 **[QUICK_REFERENCE.md](./QUICK_REFERENCE.md)** - Start here!

- Quick answers to both questions
- Behavior tables
- Configuration commands
- Best practices
- Available in both Chinese and English

### For Chinese Users / 中文用户

🇨🇳 **[检查结果.md](./检查结果.md)** - 完整的中文答案

- 详细的问题回答
- 代码证据和分析
- 安全影响说明
- 使用建议

### For Detailed Technical Analysis / 详细技术分析

📖 **[BEHAVIOR_ANALYSIS.md](./BEHAVIOR_ANALYSIS.md)** - English technical deep dive

- Complete code analysis
- Authentication flow explanation
- Security implications
- Code references with line numbers
- Recommendations for administrators and users

### For Investigation Overview / 调查概览

📊 **[INVESTIGATION_SUMMARY.md](./INVESTIGATION_SUMMARY.md)** - Investigation summary

- What was investigated
- What was delivered
- Key findings
- Conclusion
- How to run tests

## Quick Answers

### Question 1: Empty Key Behavior

✅ **Users CAN still log in with just their password**

When 2FA is enabled globally but a user's key is empty:

- 2FA is automatically bypassed for that user
- Login succeeds with username and password only
- No OTP field is shown
- This is a safety feature to prevent lockout

### Question 2: User-Specific Keys

✅ **Each user has their own separate TOTP key**

Users do NOT share keys:

- Each user has their own UCI section: `config login 'username'`
- Keys are stored per-user: `2fa.root.key`, `2fa.admin.key`, etc.
- Each user generates their own key and scans their own QR code
- Completely independent configuration per user

## Related Files

### Tests

Automated tests to verify these behaviors:

- `../tests/e2e/empty-key-behavior.spec.ts` - Tests empty key bypass
- `../tests/e2e/user-specific-keys.spec.ts` - Tests user isolation

Run tests:

```bash
npm run test:e2e
```

### Code Locations

Key code files analyzed:

- `../luci-app-2fa/root/usr/share/luci/auth.d/2fa.uc` - Authentication plugin
- `../luci-app-2fa/root/usr/share/rpcd/ucode/2fa.uc` - RPC backend
- `../luci-app-2fa/root/etc/config/2fa` - UCI configuration

## Conclusion

Both behaviors are **working correctly as designed**:

1. ✅ Empty key bypass is a safety feature (prevents lockout)
2. ✅ User-specific keys provide proper isolation (security and flexibility)

**No code changes are needed.** This investigation adds comprehensive documentation and tests to verify and explain these behaviors.

---

_Investigation completed: 2026-02-04_
