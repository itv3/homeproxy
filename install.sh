#!/bin/sh

set -eu

REPO="itv3/homeproxy"
ASSET="luci-app-homeproxy-custom_all.apk"
TMP_APK="/tmp/$ASSET"
URL="https://github.com/$REPO/releases/latest/download/$ASSET"
KEY_NAME="homeproxy-custom.pem"
KEY_URL="https://github.com/$REPO/releases/latest/download/$KEY_NAME"
REPO_LIST="/etc/apk/repositories.d/homeproxy-custom.list"
REPO_LIST_URL="https://github.com/$REPO/releases/latest/download/homeproxy-custom.list"

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
wget -O "$REPO_LIST" "$REPO_LIST_URL"

echo "update package index"
if apk update; then
	echo "install packages from repository"
	apk add luci-app-homeproxy luci-i18n-homeproxy-zh-cn
else
	echo "warning: repository update failed, falling back to direct APK install" >&2
	echo "download: $URL"
	wget -O "$TMP_APK" "$URL"

	echo "install package"
	apk add --allow-untrusted "$TMP_APK"
	rm -f "$TMP_APK"
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
apk list -I | grep luci-app-homeproxy || true
echo "success"
