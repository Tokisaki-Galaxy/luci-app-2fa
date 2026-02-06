# LuCI Authentication Plugin Mechanism Patch

This directory contains patches that need to be applied to the upstream LuCI repository to enable the authentication plugin mechanism required for 2FA support.

## Quick Installation (Recommended)

For easy installation on OpenWrt 23.05 or higher, use our automated installation script:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Tokisaki-Galaxy/luci-app-2fa@main/luci-patch/install.sh | sh
```

The script will:
1. ✅ Check your OpenWrt version (requires 23.05+)
2. 📋 Show you the list of files that will be patched
3. ⚠️ Ask for your confirmation
4. 📥 Download patches from GitHub via jsdelivr CDN
5. 🔧 Apply patches to your system
6. 🔄 Restart required services
7. 📝 Show post-installation instructions

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

4. **Authentication Settings UI**: A new "Authentication" menu item is added under System > Administration:
   - View at `/www/luci-static/resources/view/system/exauth.js`
   - Allows enabling/disabling external authentication globally
   - Allows enabling/disabling individual authentication plugins

5. **listAuthPlugins RPC Method**: Added to the `luci` ubus object:
   - Returns list of installed authentication plugins
   - Returns global `external_auth` setting status

## File Mapping

### Origin Files (from upstream LuCI)

| Origin File | LuCI Source Path |
|---|---|
| `origin/dispatcher.uc` | `modules/luci-base/ucode/dispatcher.uc` |
| `origin/sysauth.ut` | `modules/luci-base/ucode/template/sysauth.ut` |
| `origin/bootstrap-sysauth.ut` | `themes/luci-theme-bootstrap/ucode/template/themes/bootstrap/sysauth.ut` |
| `origin/luci-mod-system.json` | `modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json` |
| `origin/luci` | `modules/luci-base/root/usr/share/rpcd/ucode/luci` |
| `origin/luci-base.json` | `modules/luci-base/root/usr/share/rpcd/acl.d/luci-base.json` |

### Patched Files (to deploy)

| Patch File | OpenWrt Deployment Path |
|---|---|
| `patch/dispatcher.uc` | `/usr/share/ucode/luci/dispatcher.uc` |
| `patch/sysauth.ut` | `/usr/share/ucode/luci/template/sysauth.ut` |
| `patch/bootstrap-sysauth.ut` | `/usr/share/ucode/luci/template/themes/bootstrap/sysauth.ut` |
| `patch/luci-mod-system.json` | `/usr/share/luci/menu.d/luci-mod-system.json` |
| `patch/luci` | `/usr/share/rpcd/ucode/luci` |
| `patch/luci-base.json` | `/usr/share/rpcd/acl.d/luci-base.json` |
| `patch/view/system/exauth.js` | `/www/luci-static/resources/view/system/exauth.js` |

## How to Apply

### Method 1: Automated Installation (Recommended)

Use the automated installation script for OpenWrt 23.05+:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Tokisaki-Galaxy/luci-app-2fa@main/luci-patch/install.sh | sh
```

This is the easiest method and handles everything automatically.

### Method 2: Manual Installation (For OpenWrt)

Copy `patch` folder files to your OpenWrt system at the corresponding paths:

```bash
# Dispatcher and templates
cp patch/dispatcher.uc /usr/share/ucode/luci/dispatcher.uc
cp patch/sysauth.ut /usr/share/ucode/luci/template/sysauth.ut
cp patch/bootstrap-sysauth.ut /usr/share/ucode/luci/template/themes/bootstrap/sysauth.ut

# Menu configuration
cp patch/luci-mod-system.json /usr/share/luci/menu.d/luci-mod-system.json

# RPC backend
cp patch/luci /usr/share/rpcd/ucode/luci

# ACL configuration
cp patch/luci-base.json /usr/share/rpcd/acl.d/luci-base.json

# Authentication settings view
cp patch/view/system/exauth.js /www/luci-static/resources/view/system/exauth.js

# Clear cache and restart services
rm -f /tmp/luci-indexcache*
/etc/init.d/rpcd restart
```

