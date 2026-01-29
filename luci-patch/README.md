# LuCI Authentication Plugin Mechanism Patch

This directory contains patches that need to be applied to the upstream LuCI repository to enable the authentication plugin mechanism required for 2FA support.

## What This Patch Adds

This patch adds a **generic, non-hardcoded authentication plugin mechanism** to LuCI's dispatcher. It allows any package to add additional authentication factors (not just 2FA) without modifying core LuCI files.

### New Features:

1. **Plugin Directory**: `/usr/share/luci/auth.d/`
   - Authentication plugins are loaded automatically from this directory
   - Each plugin is a ucode file (`.uc`) that exports a standard interface

2. **Plugin Interface**:
```javascript
{
    name: 'string',        // Plugin identifier (e.g., '2fa', 'captcha', 'ip-whitelist')
    priority: number,      // Execution order (lower = first, default: 50)
    
    // Called after password verification succeeds
    // Return { required: true } if additional auth is needed
    check: function(http, user) {
        return {
            required: bool,
            fields: [{          // Additional form fields to render
                name: 'field_name',
                type: 'text',
                label: 'Field Label',
                placeholder: '...',
                // ... other HTML input attributes
            }],
            message: 'Message to display to user'
        };
    },
    
    // Called to verify the additional authentication
    verify: function(http, user) {
        return {
            success: bool,
            message: 'Error message if failed'
        };
    }
}
```

3. **Template Updates**: The `sysauth.ut` templates are updated to:
   - Render additional form fields from auth plugins
   - Display plugin-specific error messages
   - Support multiple auth plugins simultaneously

## How to Apply

### For OpenWrt Build System

Add to your feeds.conf.default or create a patch in your custom files:

```bash
# In your OpenWrt build directory
cd feeds/luci
patch -p1 < /path/to/0001-add-auth-plugin-mechanism.patch
```

### For Existing Installation

```bash
# Backup original files first
cp /usr/share/ucode/luci/dispatcher.uc /usr/share/ucode/luci/dispatcher.uc.bak
cp /usr/share/ucode/luci/template/sysauth.ut /usr/share/ucode/luci/template/sysauth.ut.bak
cp /usr/share/ucode/luci/template/themes/bootstrap/sysauth.ut /usr/share/ucode/luci/template/themes/bootstrap/sysauth.ut.bak

# Apply patch
cd /usr/share/ucode/luci
patch -p3 < /path/to/0001-add-auth-plugin-mechanism.patch
```

## Upstream Submission

This patch is designed to be submitted to the upstream LuCI repository. It:

- Follows LuCI coding style (same indentation, variable naming)
- Is fully generic (no 2FA-specific code in core files)
- Is backwards compatible (existing installations work unchanged)
- Provides a clean plugin API for future authentication extensions

Potential upstream PR: This mechanism could be used for:
- Two-Factor Authentication (TOTP/HOTP)
- CAPTCHA verification
- IP address whitelisting
- Time-based access restrictions
- Hardware token authentication (FIDO2/WebAuthn)
