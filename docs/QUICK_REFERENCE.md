# 2FA 插件行为快速参考 / 2FA Plugin Quick Reference

## 问题答案 / Answers

### 问题 1: 密钥为空会怎样? / Q1: What if key is empty?

**❌ 不会锁定 / NOT locked out**

```
全局2FA: 启用 / Enabled
用户密钥: 空 / Empty
结果 / Result: ✅ 可以登录 / Can login
需要 / Required: 只需密码 / Password only
```

### 问题 2: 用户共享密钥吗? / Q2: Do users share keys?

**❌ 不共享 / NOT shared**

```
Root:  密钥A / Key A  → 独立的TOTP / Independent TOTP
Admin: 密钥B / Key B  → 独立的TOTP / Independent TOTP
User1: 密钥C / Key C  → 独立的TOTP / Independent TOTP
```

## 代码位置 / Code Locations

```javascript
// 检查密钥是否为空 / Check if key is empty
// 文件 / File: auth.d/2fa.uc, 行 / Line: 372
let key = ctx.get('2fa', safe_username, 'key');
if (!key || key == '')
    return false;  // 跳过2FA / Bypass 2FA

// UCI 配置 / UCI Config
// 文件 / File: root/etc/config/2fa
config login 'root'      // Root用户独立配置 / Root's config
    option key 'XXX'
config login 'admin'     // Admin用户独立配置 / Admin's config
    option key 'YYY'
```

## 行为表 / Behavior Table

| 场景 / Scenario      | 全局启用 / Global | 用户密钥 / User Key | 登录 / Login             | OTP字段 / OTP Field |
| -------------------- | ----------------- | ------------------- | ------------------------ | ------------------- |
| 正常2FA / Normal 2FA | ✅                | ✅ 有效 / Valid     | 需要OTP / Need OTP       | ✅ 显示 / Show      |
| 空密钥 / Empty Key   | ✅                | ❌ 空 / Empty       | 仅需密码 / Password only | ❌ 不显示 / Hidden  |
| 2FA禁用 / Disabled   | ❌                | 任意 / Any          | 仅需密码 / Password only | ❌ 不显示 / Hidden  |

## 配置命令 / Configuration Commands

```bash
# 为root设置密钥 / Set root key
uci set 2fa.root.key='JBSWY3DPEHPK3PXP'
uci commit 2fa

# 为admin设置不同的密钥 / Set different key for admin
uci set 2fa.admin=login
uci set 2fa.admin.key='GEZDGNBVGY3TQOJQ'
uci commit 2fa

# 查看密钥 / View keys
uci get 2fa.root.key
uci get 2fa.admin.key
```

## 安全建议 / Security Recommendations

### ✅ 推荐做法 / Recommended

1. **渐进部署 / Gradual Deployment**
   - 先为自己设置 / Set up for yourself first
   - 测试登录 / Test login
   - 再为其他人启用 / Then enable for others

2. **保留后备 / Keep Backup**
   - 保留一个无2FA的管理员账户 / Keep one admin without 2FA
   - 或使用IP白名单 / Or use IP whitelist for LAN

3. **独立密钥 / Separate Keys**
   - 每个用户生成自己的密钥 / Each user generates own key
   - 用自己的认证器应用 / Use own authenticator app
   - 不要共享二维码 / Don't share QR codes

### ❌ 不要这样做 / Don't Do This

- ❌ 为所有用户启用但不设置密钥 / Enable for all without setting keys
- ❌ 尝试共享TOTP密钥 / Try to share TOTP keys
- ❌ 在没有后备方案时启用严格模式 / Enable strict mode without backup

## 测试 / Testing

```bash
# 运行所有测试 / Run all tests
npm test

# 运行E2E测试 / Run E2E tests
npm run test:e2e

# 运行特定测试 / Run specific tests
npx playwright test tests/e2e/empty-key-behavior.spec.ts
npx playwright test tests/e2e/user-specific-keys.spec.ts
```

## 文档 / Documentation

- 📖 完整文档 / Full docs: `docs/BEHAVIOR_ANALYSIS.md`
- 🇨🇳 中文答案 / Chinese: `docs/检查结果.md`
- 📋 总结 / Summary: `docs/INVESTIGATION_SUMMARY.md`
- 🚀 本文件 / This file: `docs/QUICK_REFERENCE.md`

## 总结 / Summary

✅ **空密钥 = 安全跳过** / Empty key = Safe bypass  
✅ **每个用户 = 独立密钥** / Each user = Separate key  
✅ **按设计工作** / Working as designed  
✅ **无需修改** / No changes needed

---

_创建日期 / Created: 2026-02-04_
