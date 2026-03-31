<div align="center">

<img src="https://img.shields.io/badge/OpenWrt-2FA%20Authentication-blue?style=flat-square&logo=openwrt" alt="OpenWrt 2FA" />
<img src="https://img.shields.io/badge/License-Apache%202.0-green?style=flat-square" alt="License" />
<img src="https://img.shields.io/badge/LuCI-Plugin%20Architecture-orange?style=flat-square&logo=lua" alt="LuCI Plugin" />

# 🔐 LuCI-App-2FA

**LuCI 2-Factor Authentication (2FA) Plugin for OpenWrt**

[English](#english) | [简体中文](#简体中文)

</div>

---

## English

> **Note:**  
> This plugin requires LuCI with the **plugin UI architecture** (introduced in commit `617f364`) and the **authentication plugin mechanism**.  
> These changes are being upstreamed via [openwrt/luci#8281](https://github.com/openwrt/luci/pull/8281).

LuCI 2-Factor Authentication (2FA) plugin for OpenWrt.

This plugin adds two-factor authentication support to the LuCI web interface, enhancing security by requiring a one-time password (OTP) in addition to the regular username and password.

### ✨ Features

- 🔑 **TOTP (Time-based OTP)**: Compatible with Google Authenticator, Authy, and other TOTP apps
- 📴 **HOTP (Counter-based OTP)**: Works offline without requiring time synchronization
- 🛡️ **Rate Limiting**: Configurable protection against brute-force attacks
- 🌐 **IP Whitelist**: Bypass 2FA for trusted networks (e.g., LAN)
- ⏰ **Time Calibration Check**: Automatic detection of uncalibrated system clock
- 🔒 **Strict Mode**: Block login when system time is not calibrated

### 🏗️ Architecture

This plugin uses LuCI's new **plugin UI architecture**:

- **Backend Plugin**: `/usr/share/ucode/luci/plugins/auth/login/<uuid>.uc`
- **UI Plugin**: `/www/luci-static/resources/view/plugins/<uuid>.js`
- **Configuration**: UCI `luci_plugins` config

The plugin integrates into **System → Plugins** menu, providing a consistent experience with other LuCI plugins.

### 📦 Installation

#### For LuCI with Plugin Architecture (Recommended)

If your LuCI already has the plugin UI architecture and auth plugin mechanism:

```bash
# Install from opkg feed
wget https://tokisaki-galaxy.github.io/luci-app-2fa/all/key-build.pub -O /tmp/key-build.pub
opkg-key add /tmp/key-build.pub
echo "src/gz luci-app-2fa https://tokisaki-galaxy.github.io/luci-app-2fa/all" >> /etc/opkg/customfeeds.conf
opkg update
opkg install luci-app-2fa
```

#### Building from Source

```bash
# Clone into your OpenWrt package feeds
git clone https://github.com/Tokisaki-Galaxy/luci-app-2fa.git package/luci-app-2fa

# Enable in menuconfig
make menuconfig  # Select LuCI → Applications → luci-app-2fa

# Build
make package/luci-app-2fa/compile V=s
```

### ⚙️ Configuration

1. Navigate to **System → Plugins** in LuCI
2. Find **Two-Factor Authentication** plugin
3. Configure your secret key and enable the plugin
4. Global plugin system must be enabled: `luci_plugins.global.enabled='1'`
5. Auth login plugins must be enabled: `luci_plugins.global.auth_login_enabled='1'`

### 🔧 UCI Configuration

Configuration is stored in `/etc/config/luci_plugins`:

```
config global 'global'
    option enabled '1'
    option auth_login_enabled '1'

config auth_login 'bb4ea47fcffb44ec9bb3d3673c9b4ed2'
    option enabled '1'
    option name 'Two-Factor Authentication'
    option key_root 'JBSWY3DPEHPK3PXP'
    option type_root 'totp'
    option step_root '30'
    option rate_limit_enabled '1'
    option rate_limit_max_attempts '5'
    option rate_limit_window '60'
    option rate_limit_lockout '300'
```

### 🧪 Testing

Generate an OTP for testing:

```bash
/usr/libexec/generate_otp.uc root --plugin=bb4ea47fcffb44ec9bb3d3673c9b4ed2
```

### 🙏 Credits

- **Original PR**: [openwrt/luci#7069](https://github.com/openwrt/luci/pull/7069)
- **Original Author**: Christian Marangi (ansuelsmth@gmail.com)
- **QR Code Library**: uqr (MIT licensed) - based on [uqr by Anthony Fu](https://github.com/unjs/uqr)

---

## 简体中文

> **注意：**  
> 此插件需要具有**插件UI架构**（在提交 `617f364` 中引入）和**认证插件机制**的 LuCI。  
> 这些更改正在通过 [openwrt/luci#8281](https://github.com/openwrt/luci/pull/8281) 推进上游合并。

OpenWrt 的 LuCI 双因素认证（2FA）插件。

此插件为 LuCI Web 界面添加了双因素认证支持，通过要求输入一次性密码 (OTP) 来增强安全性。

### ✨ 功能特性

- 🔑 **TOTP（基于时间的 OTP）**: 与 Google Authenticator、Authy 等应用兼容
- 📴 **HOTP（基于计数器的 OTP）**: 离线工作，无需时间同步
- 🛡️ **速率限制**: 可配置的暴力破解防护
- 🌐 **IP 白名单**: 受信任网络（如局域网）可跳过 2FA
- ⏰ **时间校准检查**: 自动检测未校准的系统时钟
- 🔒 **严格模式**: 系统时间未校准时阻止登录

### 🏗️ 架构

此插件使用 LuCI 的新**插件UI架构**：

- **后端插件**: `/usr/share/ucode/luci/plugins/auth/login/<uuid>.uc`
- **UI插件**: `/www/luci-static/resources/view/plugins/<uuid>.js`
- **配置**: UCI `luci_plugins` 配置

插件集成到**系统 → 插件**菜单，与其他 LuCI 插件提供一致的体验。

### 📦 安装方式

#### 适用于具有插件架构的 LuCI（推荐）

如果您的 LuCI 已经具有插件UI架构和认证插件机制：

```bash
# 从 opkg 源安装
wget https://tokisaki-galaxy.github.io/luci-app-2fa/all/key-build.pub -O /tmp/key-build.pub
opkg-key add /tmp/key-build.pub
echo "src/gz luci-app-2fa https://tokisaki-galaxy.github.io/luci-app-2fa/all" >> /etc/opkg/customfeeds.conf
opkg update
opkg install luci-app-2fa
```

#### 从源码编译

```bash
# 克隆到 OpenWrt 软件包目录
git clone https://github.com/Tokisaki-Galaxy/luci-app-2fa.git package/luci-app-2fa

# 在 menuconfig 中启用
make menuconfig  # 选择 LuCI → Applications → luci-app-2fa

# 编译
make package/luci-app-2fa/compile V=s
```

### ⚙️ 配置步骤

1. 在 LuCI 中导航到**系统 → 插件**
2. 找到**双因素认证**插件
3. 配置密钥并启用插件
4. 全局插件系统必须启用: `luci_plugins.global.enabled='1'`
5. 认证登录插件必须启用: `luci_plugins.global.auth_login_enabled='1'`

### 🔧 UCI 配置文件

配置保存在 `/etc/config/luci_plugins`:

```
config global 'global'
    option enabled '1'
    option auth_login_enabled '1'

config auth_login 'bb4ea47fcffb44ec9bb3d3673c9b4ed2'
    option enabled '1'
    option name 'Two-Factor Authentication'
    option key_root 'JBSWY3DPEHPK3PXP'
    option type_root 'totp'
    option step_root '30'
    option rate_limit_enabled '1'
    option rate_limit_max_attempts '5'
    option rate_limit_window '60'
    option rate_limit_lockout '300'
```

### 🧪 测试

生成 OTP 用于测试：

```bash
/usr/libexec/generate_otp.uc root --plugin=bb4ea47fcffb44ec9bb3d3673c9b4ed2
```

### 🙏 致谢与来源

- **原始 PR**: [openwrt/luci#7069](https://github.com/openwrt/luci/pull/7069)
- **原始作者**: Christian Marangi (ansuelsmth@gmail.com)
- **二维码库**: uqr (MIT 许可证) - 基于 [Anthony Fu 的 uqr](https://github.com/unjs/uqr)
