#
# Copyright (C) 2024 Christian Marangi <ansuelsmth@gmail.com>
#
# This is free software, licensed under the Apache License, Version 2.0.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-2fa

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Tokiskai Galaxy <moebest@outlook.jp>

LUCI_TITLE:=LuCI 2-Factor Authentication
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

define Package/luci-app-2fa/conffiles
/etc/config/2fa
endef

define Package/luci-app-2fa/prerm
#!/bin/sh
# Restore original uhttpd handler before removal
if [ -z "$${IPKG_INSTROOT}" ] && [ -f /etc/config/uhttpd ]; then
	DEFAULT_HANDLER="/cgi-bin/luci=/usr/share/ucode/luci/uhttpd.uc"
	TFA_HANDLER="/cgi-bin/luci=/usr/share/ucode/luci/uhttpd-2fa.uc"
	
	# Check if our handler is currently in use
	if uci -q get uhttpd.main.ucode_prefix | grep -sq "uhttpd-2fa.uc"; then
		# Remove our handler and restore the default
		uci del_list uhttpd.main.ucode_prefix="$$TFA_HANDLER" 2>/dev/null
		# Add default back if not already present
		if ! uci -q get uhttpd.main.ucode_prefix | grep -sq "$$DEFAULT_HANDLER"; then
			uci add_list uhttpd.main.ucode_prefix="$$DEFAULT_HANDLER"
		fi
		uci commit uhttpd
		# Restart uhttpd
		if [ -x /etc/init.d/uhttpd ]; then
			/etc/init.d/uhttpd restart 2>/dev/null || true
		fi
	fi
fi
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot
