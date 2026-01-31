# Copilot Agent 运行环境

## 环境配置
- **可用工具**: `jq`, `xvfb`, `tree`, `ripgrep`, `socat`, `sshpass`, `qemu-user-static`
- **Playwright**: 已预装，优先用于 E2E 测试和动态页面验证。
- **OpenWrt**:
  - 镜像: `openwrt/rootfs:x86-64-24.10.4` (含完整 opkg)
  - 源码: `openwrt/luci` (与仓库代码同级)
  - 编译链: `build-essential`, `gettext`, `libssl-dev`, `zlib1g-dev`

## ⚠️ 关键流程：LuCI 服务启动
**必须严格遵守启动顺序：ubusd -> procd -> rpcd -> uhttpd**
(见下文“一键启动脚本”，否则会导致 `Failed to connect to ubus` 或 `left-hand side expression is null`)
这是压缩后的版本。我移除了冗余的解释性文字（如“为什么要按顺序启动”的原理说明，改为直接的指令），合并了相似的命令，并将多行脚本压缩为单行或紧凑块。

核心逻辑（启动顺序、路径映射、关键命令、排查表、测试选择器）完全保留。

**一键启动脚本 (安装依赖+配置+启动):**
```bash
docker run -d --name openwrt-luci -p 8080:80 openwrt/rootfs:x86-64-24.10.4 /bin/ash -c '
mkdir -p /var/lock /var/run && opkg update && opkg install luci luci-base luci-compat
/sbin/ubusd & sleep 1 && /sbin/procd & sleep 2 && /sbin/rpcd & sleep 1
/usr/sbin/uhttpd -f -h /www -r OpenWrt -x /cgi-bin -u /ubus -t 60 -T 30 -A 1 -n 3 -N 100 -R -p 0.0.0.0:80 &
echo -e "password\npassword" | passwd root
uci set luci.themes.Bootstrap=/luci-static/bootstrap && uci commit luci
tail -f /dev/null'
# 访问: http://localhost:8080 (root/password)
```

## 3. 开发工作流

### 文件部署映射
| 类型 | 本地源码路径 (`luci-app-tailscale-community/...`) | 容器路径 (`openwrt-luci:...`) |
|---|---|---|
| **JS** | `htdocs/luci-static/resources/view/tailscale.js` | `/www/luci-static/resources/view/tailscale.js` |
| **Menu** | `root/usr/share/luci/menu.d/*.json` | `/usr/share/luci/menu.d/` |
| **ACL** | `root/usr/share/rpcd/acl.d/*.json` | `/usr/share/rpcd/acl.d/` |
| **Ucode**| `root/usr/share/rpcd/ucode/*.uc` | `/usr/share/rpcd/ucode/` |

### 部署命令 (示例)
```bash
# 1. 复制文件
docker cp [LocalPath] openwrt-luci:[ContainerPath]
# 2. 只有首次需创建 UCI 配置
docker exec openwrt-luci sh -c '[ ! -f /etc/config/tailscale ] && printf "config settings settings\n\toption enabled 0\n\toption port 41641\n\toption fw_mode nftables\n" > /etc/config/tailscale'
# 3. 重载 rpcd (更新 ACL/Ucode 后必须)
docker exec openwrt-luci sh -c "kill -9 \$(pgrep rpcd) && /sbin/rpcd &"
# 4. 验证 RPC
docker exec openwrt-luci ubus call tailscale get_status
```

### 代码检查与测试
- **Lint/Fmt**: `npx tsc -b`, `npm run lint`, `npx prettier --write .`, `npx knip`
- **Test**: `npx vitest`
- **i18n**: `cd luci && ./build/i18n-sync.sh applications/luci-app-tailscale-community`
- **Ucode调试**: `docker exec openwrt-luci ucode /usr/share/rpcd/ucode/tailscale.uc`

### Playwright 登录片段
```js
await page.goto('http://localhost:8080/cgi-bin/luci/');
await page.getByRole('textbox', { name: 'Password' }).fill('password');
await page.getByRole('button', { name: 'Log in' }).click();
```

## 4. 故障排查
| 现象 | 原因 | 修复 |
|---|---|---|
| `Failed to connect to ubus` | ubusd 挂了 | `/sbin/ubusd &` |
| 500 / `left-hand side expression is null` | procd 挂了 | `/sbin/procd &` |
| 插件 RPC 错误 | rpcd 未重载或 ACL 错 | 重启 rpcd / 查 ACL |
| 主题渲染错 | 缺少主题配置 | `uci set luci.themes.Bootstrap=/luci-static/bootstrap` |

**注**: 参考 `openwrt/luci` 源码保持一致性；LLM 写 ucode 易有幻觉，请参考官方文档。
