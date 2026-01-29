# luci-app-2fa

LuCI 2-Factor Authentication (2FA) app for OpenWrt.

This package adds two-factor authentication support to the LuCI web interface, enhancing security by requiring a one-time password (OTP) in addition to the regular username and password.

## Features

- **TOTP (Time-based OTP)**: Requires synchronized time. Compatible with Google Authenticator, Authy, and other TOTP apps.
- **HOTP (Counter-based OTP)**: Works offline without requiring time synchronization.
- **QR Code Generation**: Easy setup with authenticator apps by scanning a QR code.
- **Base32 Key Generation**: Secure random key generation for OTP secrets.

## Screenshots

![2FA Settings Page](https://github.com/user-attachments/assets/385ed6de-f30c-4cd1-9881-2516a8c05152)

## Installation

### From OpenWrt Package Repository

```bash
opkg update
opkg install luci-app-2fa
```

### Manual Installation

1. Copy the package files to your OpenWrt system
2. Restart rpcd: `/etc/init.d/rpcd restart`
3. Access LuCI and navigate to System → 2-Factor Auth

## Configuration

1. Navigate to **System → 2-Factor Auth** in LuCI
2. Click **Generate Key** to create a new secret key
3. Scan the QR code with your authenticator app (Google Authenticator, Authy, etc.)
4. Enable the "Enable 2FA" checkbox
5. Click **Save & Apply**

## UCI Configuration

The configuration is stored in `/etc/config/2fa`:

```
config settings 'settings'
    option enabled '0'

config login 'root'
    option key ''
    option type 'totp'
    option step '30'
    option counter '0'
```

## Credits

This package is based on the original PR by Christian Marangi:
- Original PR: https://github.com/openwrt/luci/pull/7069
- QR Code library (uqr): MIT licensed, based on [uqr by Anthony Fu](https://github.com/unjs/uqr)

## License

Apache-2.0

## See Also

- [OpenWrt](https://openwrt.org/)
- [LuCI](https://github.com/openwrt/luci)
