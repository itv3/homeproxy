#!/bin/sh

set -eu

REPO="itv3/homeproxy"
PKG_NAME="homeproxy-custom"
ASSET="homeproxy-custom_all.apk"
TMP_APK="/tmp/$ASSET"
URL="https://github.com/$REPO/releases/latest/download/$ASSET"
KEY_NAME="homeproxy-custom.pem"
KEY_URL="https://github.com/$REPO/releases/latest/download/$KEY_NAME"
REPO_LIST="/etc/apk/repositories.d/homeproxy-custom.list"
REPO_INDEX_URL="https://github.com/$REPO/releases/latest/download/Packages.adb"

trap 'rm -f "$TMP_APK"' EXIT

echo "HomeProxy Custom installer"

if [ ! -x /usr/bin/apk ]; then
	echo "error: this installer currently supports apk-based OpenWrt/ImmortalWrt only"
	exit 1
fi

if [ ! -x /usr/bin/wget ] && [ ! -x /bin/wget ]; then
	echo "error: wget is required"
	exit 1
fi

mkdir -p /etc/apk/keys /etc/apk/repositories.d

echo "install repository key"
wget -O "/etc/apk/keys/$KEY_NAME" "$KEY_URL"

echo "configure repository"
printf '%s\n' "$REPO_INDEX_URL" > "$REPO_LIST"

echo "remove standalone translation package if installed"
apk del luci-i18n-homeproxy-zh-cn 2>/dev/null || true

install_direct_apk() {
	echo "download: $URL"
	wget -O "$TMP_APK" "$URL"

	echo "install package"
	apk add --allow-untrusted "$TMP_APK"
}

echo "update package index"
if apk update && apk add "$PKG_NAME"; then
	echo "installed from repository"
else
	echo "warning: repository install failed, falling back to direct APK install" >&2
	install_direct_apk
fi

echo "clean .apk-new files"
find /etc/homeproxy /etc/config -name "*.apk-new" -exec rm -f {} \; 2>/dev/null || true

echo "restart services"
rm -f /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache/ 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/homeproxy restart 2>/dev/null || true

echo "installed:"
apk list -I | grep -E '^(homeproxy-custom|luci-app-homeproxy)' || true
echo "success"
