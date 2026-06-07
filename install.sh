#!/bin/sh

set -eu

REPO="itv3/homeproxy"
ASSET="luci-app-homeproxy-custom_all.apk"
TMP_APK="/tmp/$ASSET"
URL="https://github.com/$REPO/releases/latest/download/$ASSET"

echo "HomeProxy Custom installer"

if [ ! -x /usr/bin/apk ]; then
	echo "error: this installer currently supports apk-based OpenWrt/ImmortalWrt only"
	exit 1
fi

if [ ! -x /usr/bin/wget ] && [ ! -x /bin/wget ]; then
	echo "error: wget is required"
	exit 1
fi

echo "download: $URL"
wget -O "$TMP_APK" "$URL"

echo "install package"
apk add --allow-untrusted "$TMP_APK"
rm -f "$TMP_APK"

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
