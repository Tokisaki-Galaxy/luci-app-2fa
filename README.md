<div align="center">

<img src="https://img.shields.io/badge/OpenWrt-2FA%20Authentication-blue?style=flat-square&logo=openwrt" alt="OpenWrt 2FA" />
<img src="https://img.shields.io/badge/License-Apache%202.0-green?style=flat-square" alt="License" />
<img src="https://img.shields.io/badge/LuCI-Web%20Interface-orange?style=flat-square&logo=lua" alt="LuCI" />

# 🔐 [WIP]LuCI-App-2FA

## ⚠️ 需要先通过交互式补丁脚本完成 LuCI 侧改动  need to apply LuCI patch first
**请先运行：`curl -fsSL https://cdn.jsdelivr.net/gh/Tokisaki-Galaxy/luci-app-2fa@main/luci-patch/install.sh | sh` 进行交互式 patch；相关变更正在上游仓库以 [openwrt/luci#8281](https://github.com/openwrt/luci/pull/8281) PR 推进中。**

**Run first: `curl -fsSL https://cdn.jsdelivr.net/gh/Tokisaki-Galaxy/luci-app-2fa@main/luci-patch/install.sh | sh` to apply LuCI patch interactively; the changes are being upstreamed via [openwrt/luci#8281](https://github.com/openwrt/luci/pull/8281).**

**LuCI 2-Factor Authentication (2FA) app for OpenWrt**

[English](#english) | [简体中文](#简体中文)

</div>

---

## English

> **Important:**  
> This repository **must be used together with the new authentication plugin interface** provided by [openwrt/luci#8281](https://github.com/openwrt/luci/pull/8281).  
> The PR modifies LuCI's authentication logic to support plugins (see [`luci-patch`](luci-patch/README.md)), which is required for 2FA to work.  
> If you build LuCI yourself, you need to manually apply the patch in the `luci-patch` directory.

LuCI 2-Factor Authentication (2FA) app for OpenWrt.

This package adds two-factor authentication support to the LuCI web interface, enhancing security by requiring a one-time password (OTP) in addition to the regular username and password.

### ✨ Features

- 🔑 **TOTP (Time-based OTP)**: Requires synchronized time. Compatible with Google Authenticator, Authy, and other TOTP apps.
- 📴 **HOTP (Counter-based OTP)**: Works offline without requiring time synchronization.
- 📱 **QR Code Generation**: Easy setup with authenticator apps by scanning a QR code.
- 🎲 **Base32 Key Generation**: Secure random key generation for OTP secrets.

### 📸 Screenshots

![2FA Settings Page](https://github.com/user-attachments/assets/385ed6de-f30c-4cd1-9881-2516a8c05152)

### 📦 Installation

This plugin **requires the new authentication plugin mechanism** introduced in [openwrt/luci#8281](https://github.com/openwrt/luci/pull/8281).

#### Quick Installation (OpenWrt 23.05+)

For the easiest installation experience, use our automated script that applies the required patches:

```bash
# Step 1: Apply LuCI patches (one-time setup)
curl -fsSL https://cdn.jsdelivr.net/gh/Tokisaki-Galaxy/luci-app-2fa@main/luci-patch/install.sh | sh

# Step 2: Install the 2FA package
wget https://tokisaki-galaxy.github.io/luci-app-2fa/all/key-build.pub -O /tmp/key-build.pub
opkg-key add /tmp/key-build.pub
echo "src/gz luci-app-2fa https://tokisaki-galaxy.github.io/luci-app-2fa/all" >> /etc/opkg/customfeeds.conf
opkg update
opkg install luci-app-2fa
```

#### Manual Installation (Building from Source)

If you are building your own LuCI, you must apply the patch in the [`luci-patch`](luci-patch/) directory:

```bash
# In your LuCI source directory
cd feeds/luci
patch -p1 < /path/to/luci-app-2fa/luci-patch/0001-add-auth-plugin-mechanism.patch
```

#### Install from Custom opkg Feed (Legacy)

```bash
wget https://tokisaki-galaxy.github.io/luci-app-2fa/all/key-build.pub -O /tmp/key-build.pub
opkg-key add /tmp/key-build.pub
echo "src/gz luci-app-2fa https://tokisaki-galaxy.github.io/luci-app-2fa/all" >> /etc/opkg/customfeeds.conf
opkg update
opkg install luci-app-2fa
```

#### Manual Installation

1. Download [Release package](https://github.com/Tokisaki-Galaxy/luci-app-2fa/releases)
2. Uplaod the package to your OpenWrt system and install it
3. Access LuCI and navigate to System → 2-Factor Auth

### ⚙️ Configuration

1. Navigate to **System → 2-Factor Auth** in LuCI
2. Click **Generate Key** to create a new secret key
3. Scan the QR code with your authenticator app (Google Authenticator, Authy, etc.)
4. Enable the "Enable 2FA" checkbox
5. Click **Save & Apply**

### 🔧 UCI Configuration

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

### 🙏 Origin & Credits

This package is based on the original upstream implementation:

- **Original PR**: [openwrt/luci#7069](https://github.com/openwrt/luci/pull/7069)
- **Original Author**: Christian Marangi (ansuelsmth@gmail.com)
- **QR Code Library**: uqr (MIT licensed) - based on [uqr by Anthony Fu](https://github.com/unjs/uqr)

---

## 简体中文

OpenWrt 的 LuCI 双因素认证（2FA）应用。

此软件包为 LuCI Web 界面添加了双因素认证支持，通过要求输入一次性密码 (OTP) 来增强安全性。

### ✨ 功能特性

- 🔑 **TOTP（基于时间的 OTP）**: 需要时间同步，与 Google Authenticator、Authy 等应用兼容。
- 📴 **HOTP（基于计数器的 OTP）**: 离线工作，无需时间同步。
- 📱 **二维码生成**: 通过扫描二维码轻松设置验证器应用。
- 🎲 **Base32 密钥生成**: 为 OTP 密钥生成安全的随机密钥。

### 📸 界面截图

![2FA 设置页面](https://github.com/user-attachments/assets/385ed6de-f30c-4cd1-9881-2516a8c05152)

### 📦 安装方式

本插件**必须依赖 [openwrt/luci#8281](https://github.com/openwrt/luci/pull/8281) PR 引入的新认证插件机制**。

#### 快速安装 (OpenWrt 23.05+)

推荐使用自动化脚本进行安装，它会自动应用所需的补丁：

```bash
# 步骤 1: 应用 LuCI 补丁（一次性设置）
curl -fsSL https://cdn.jsdelivr.net/gh/Tokisaki-Galaxy/luci-app-2fa@main/luci-patch/install.sh | sh

# 步骤 2: 安装 2FA 软件包
wget https://tokisaki-galaxy.github.io/luci-app-2fa/all/key-build.pub -O /tmp/key-build.pub
opkg-key add /tmp/key-build.pub
echo "src/gz luci-app-2fa https://tokisaki-galaxy.github.io/luci-app-2fa/all" >> /etc/opkg/customfeeds.conf
opkg update
opkg install luci-app-2fa
```

#### 手动安装（从源码编译）

如果你自行编译 LuCI，请在 [`luci-patch`](luci-patch/) 目录下手动打补丁：

```bash
# 在你的 LuCI 源码目录下
cd feeds/luci
patch -p1 < /path/to/luci-app-2fa/luci-patch/0001-add-auth-plugin-mechanism.patch
```

#### 从自定义opkg软件源安装（传统方式）

```bash
wget https://tokisaki-galaxy.github.io/luci-app-2fa/all/key-build.pub -O /tmp/key-build.pub
opkg-key add /tmp/key-build.pub
echo "src/gz luci-app-2fa https://tokisaki-galaxy.github.io/luci-app-2fa/all" >> /etc/opkg/customfeeds.conf
opkg update
opkg install luci-app-2fa
```

#### 离线手动安装

1. 下载 [Release package](https://github.com/Tokisaki-Galaxy/luci-app-2fa/releases)
2. 将软件包上传到您的 OpenWrt 系统并安装
3. 访问 LuCI 并导航到 系统 → 双因素认证

### ⚙️ 配置步骤

1. 在 LuCI 中导航到 **系统 → 双因素认证**
2. 点击 **生成密钥** 创建新的密钥
3. 使用您的验证器应用（Google Authenticator、Authy 等）扫描二维码
4. 勾选 **启用 2FA** 复选框
5. 点击 **保存并应用**

### 🔧 UCI 配置文件

配置保存在 `/etc/config/2fa`:

```
config settings 'settings'
    option enabled '0'

config login 'root'
    option key ''
    option type 'totp'
    option step '30'
    option counter '0'
```

### 🙏 致谢与来源

此软件包基于上游官方实现改进：

- **原始 PR**: [openwrt/luci#7069](https://github.com/openwrt/luci/pull/7069)
- **原始作者**: Christian Marangi (ansuelsmth@gmail.com)
- **二维码库**: uqr (MIT 许可证) - 基于 [Anthony Fu 的 uqr](https://github.com/unjs/uqr)
