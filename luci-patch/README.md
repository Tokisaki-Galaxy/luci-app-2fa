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

### For Openwrt Online Patching

copy `patch` folder file and cover to following files to your OpenWrt system:

```
/usr/share/ucode/luci/dispatcher.uc
/usr/share/ucode/luci/template/sysauth.ut
/usr/share/ucode/luci/template/themes/bootstrap/sysauth.ut
```
