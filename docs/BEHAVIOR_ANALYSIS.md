# 2FA Plugin Behavior Analysis

## Questions and Answers

### Question 1: 如果这个插件启用的时候,密钥设置为空,登录界面会怎么样?会不会无法登录

**English**: If this plugin is enabled but the secret key is empty, what happens at the login interface? Will users be unable to log in?

**Answer**: **NO, users CAN still log in normally with just their password.**

#### Detailed Explanation

When the 2FA plugin is globally enabled but a user's secret key is empty, the system automatically **bypasses 2FA** for that user.

**Code Evidence** (from `luci-app-2fa/root/usr/share/luci/auth.d/2fa.uc`):

```javascript
// Line 356-377: is_2fa_enabled() function
function is_2fa_enabled(username) {
    let uci = require('uci');
    let ctx = uci.cursor();
    
    // Check if 2FA is globally enabled
    let enabled = ctx.get('2fa', 'settings', 'enabled');
    if (enabled != '1')
        return false;

    // Sanitize username
    let safe_username = sanitize_username(username);
    if (!safe_username)
        return false;

    // Check if user has a key configured
    let key = ctx.get('2fa', safe_username, 'key');
    if (!key || key == '')
        return false;  // ← Returns false if key is empty!

    return true;
}
```

**Login Flow**:

1. User enters username and password
2. After password verification, the `check()` function is called (line 506)
3. `check()` calls `is_2fa_enabled(user)` (line 528)
4. If key is empty, `is_2fa_enabled()` returns `false`
5. `check()` returns `{ required: false }` - **2FA is NOT required**
6. User can log in with just password, no OTP field shown

**Behavior Summary**:

| Global 2FA Setting | User's Key | Behavior |
|-------------------|------------|----------|
| Enabled | Has valid key | 2FA required, OTP field shown |
| Enabled | Empty or missing | 2FA **bypassed**, password-only login |
| Disabled | Any | 2FA bypassed, password-only login |

**Safety Design**: This is a **safety feature** to prevent lockout scenarios:
- If you accidentally enable 2FA globally but haven't set up keys yet
- If you lose access to your authenticator app
- You can still log in to reconfigure

---

### Question 2: 如果root启用,但是切换到另一个用户登录,他们两个是共享一个TOTP密钥吗?

**English**: If root has 2FA enabled but you switch to another user to log in, do they share the same TOTP key?

**Answer**: **NO, each user has their own separate TOTP key.**

#### Detailed Explanation

Each user has a **separate UCI configuration section** with their own individual key. Keys are **NOT shared** between users.

**Code Evidence**:

**UCI Configuration Structure** (from `luci-app-2fa/root/etc/config/2fa`):
```
config settings 'settings'
    option enabled '0'
    ...

config login 'root'          ← Separate section for 'root' user
    option key ''
    option type 'totp'
    option step '30'
    option counter '0'

# If you add another user, it would be:
# config login 'admin'       ← Separate section for 'admin' user
#     option key 'DIFFERENTKEY'
#     option type 'totp'
#     ...
```

**How Keys are Retrieved** (from `auth.d/2fa.uc` line 372):
```javascript
// The username is used as the UCI section name
let key = ctx.get('2fa', safe_username, 'key');
//                         ^^^^^^^^^^^^
//                         Section name = username
```

For example:
- Root user key: `uci get 2fa.root.key`
- Admin user key: `uci get 2fa.admin.key`
- Other user key: `uci get 2fa.username.key`

**Multi-User Example**:

```bash
# Configure root user
uci set 2fa.root.key='JBSWY3DPEHPK3PXP'
uci set 2fa.root.type='totp'

# Configure admin user with a DIFFERENT key
uci set 2fa.admin=login
uci set 2fa.admin.key='GEZDGNBVGY3TQOJQ'  # Different key!
uci set 2fa.admin.type='totp'

uci commit 2fa
```

**Behavior Summary**:

| User | Key Storage | TOTP Codes |
|------|-------------|------------|
| root | `2fa.root.key` | Generated from root's key |
| admin | `2fa.admin.key` | Generated from admin's key |
| user1 | `2fa.user1.key` | Generated from user1's key |

**Each user must**:
1. Generate their own secret key
2. Scan their own QR code with their authenticator app
3. Use their own TOTP codes during login

**Independent Configuration**:
- You can enable 2FA for some users and not others
- Each user can choose TOTP or HOTP independently
- Each user can have different time step settings

---

## Security Implications

### Empty Key Safety
The empty key bypass is intentional and safe because:
1. User still needs valid password to log in
2. Prevents complete lockout if 2FA misconfigured
3. Admin can log in to fix/configure 2FA properly

### User Separation Benefits
Having separate keys per user provides:
1. **Individual accountability**: Each user's 2FA is independent
2. **Security isolation**: Compromising one user's authenticator doesn't affect others
3. **Flexible deployment**: Can gradually roll out 2FA user-by-user
4. **Easy key rotation**: Can change one user's key without affecting others

---

## Testing

Automated tests have been created to verify both behaviors:

1. **tests/e2e/empty-key-behavior.spec.ts**: Tests login with empty key
2. **tests/e2e/user-specific-keys.spec.ts**: Tests user-specific key storage

Run tests with:
```bash
npm test
```

---

## Recommendations

### For System Administrators:

1. **Enable 2FA gradually**:
   - Set up your own key first
   - Test login thoroughly
   - Then enable for other users

2. **Always maintain a backup admin account**:
   - Keep one account without 2FA enabled
   - Or keep backup recovery codes
   - In case of authenticator loss

3. **Use IP whitelisting for LAN**:
   - Add your LAN subnet to IP whitelist
   - Bypass 2FA from trusted network
   - Full 2FA protection for WAN access

### For Users:

1. **Generate and save your key immediately** after enabling 2FA
2. **Test login with OTP** before logging out
3. **Save backup codes** or QR code securely
4. **Each user needs their own authenticator app entry** - don't try to share!

---

## Code References

| Behavior | File | Lines | Function |
|----------|------|-------|----------|
| Empty key bypass | `auth.d/2fa.uc` | 356-377 | `is_2fa_enabled()` |
| User-specific keys | `auth.d/2fa.uc` | 372 | Key retrieval |
| UCI config structure | `root/etc/config/2fa` | 13-17 | Default config |
| RPC backend | `rpcd/ucode/2fa.uc` | 381-456 | `isEnabled` method |

---

## Summary

✅ **Question 1**: Empty key = **Normal login allowed** (2FA bypassed safely)  
✅ **Question 2**: Each user = **Separate TOTP key** (not shared)

Both behaviors are **by design** and provide good security with user-friendly safety features.
