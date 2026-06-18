#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2023 Tianling Shen <cnsztl@immortalwrt.org>

set -o errexit
set -o pipefail

PKG_MGR="${1:-apk}"
RELEASE_TYPE="${2:-snapshot}"

export PKG_SOURCE_DATE_EPOCH="$(date "+%s")"
export SOURCE_DATE_EPOCH="$PKG_SOURCE_DATE_EPOCH"

BASE_DIR="$(cd "$(dirname $0)"; pwd)"
PKG_DIR="$BASE_DIR/.."

function get_mk_value() {
	awk -F "$1:=" '{print $2}' "$PKG_DIR/Makefile" | xargs
}

ORIGINAL_PKG_NAME="$(get_mk_value "PKG_NAME")"
PKG_NAME="${CUSTOM_PKG_NAME:-$ORIGINAL_PKG_NAME}"
if [ -n "${CUSTOM_PKG_VERSION:-}" ]; then
	PKG_VERSION="$CUSTOM_PKG_VERSION"
elif [ "$RELEASE_TYPE" == "release" ]; then
	PKG_VERSION="$(get_mk_value "PKG_VERSION")"
else
	PKG_VERSION="99.$PKG_SOURCE_DATE_EPOCH-r0"
fi

PKG_DESCRIPTION="${CUSTOM_PKG_DESCRIPTION:-The modern ImmortalWrt proxy platform for ARM64/AMD64}"
PKG_URL="${CUSTOM_PKG_URL:-https://github.com/itv3/homeproxy}"
PKG_ORIGIN="${CUSTOM_PKG_ORIGIN:-$ORIGINAL_PKG_NAME}"
PKG_MAINTAINER="${CUSTOM_PKG_MAINTAINER:-Tianling Shen <cnsztl@immortalwrt.org>}"

function join_by() {
	local IFS="$1"
	shift
	echo "$*"
}

APK_PROVIDES=()
APK_REPLACES=("luci-i18n-homeproxy-zh-cn")
IPK_PROVIDES=()
IPK_REPLACES=("luci-i18n-homeproxy-zh-cn")
IPK_CONFLICTS=("luci-i18n-homeproxy-zh-cn")

if [ "$PKG_NAME" != "$ORIGINAL_PKG_NAME" ]; then
	APK_PROVIDES+=("$ORIGINAL_PKG_NAME=$PKG_VERSION" "luci-i18n-homeproxy-zh-cn=$PKG_VERSION")
	APK_REPLACES+=("$ORIGINAL_PKG_NAME")
	IPK_PROVIDES+=("$ORIGINAL_PKG_NAME")
	IPK_REPLACES+=("$ORIGINAL_PKG_NAME")
	IPK_CONFLICTS+=("$ORIGINAL_PKG_NAME")
fi

APK_PROVIDES_TEXT="$(join_by " " "${APK_PROVIDES[@]}")"
APK_REPLACES_TEXT="$(join_by " " "${APK_REPLACES[@]}")"
IPK_PROVIDES_TEXT="$(join_by ", " "${IPK_PROVIDES[@]}")"
IPK_REPLACES_TEXT="$(join_by ", " "${IPK_REPLACES[@]}")"
IPK_CONFLICTS_TEXT="$(join_by ", " "${IPK_CONFLICTS[@]}")"

TEMP_DIR="$(mktemp -d -p $BASE_DIR)"
TEMP_PKG_DIR="$TEMP_DIR/$PKG_NAME"
mkdir -p "$TEMP_PKG_DIR/lib/upgrade/keep.d/"
mkdir -p "$TEMP_PKG_DIR/usr/lib/lua/luci/i18n/"
mkdir -p "$TEMP_PKG_DIR/www/"
if [ "$PKG_MGR" == "apk" ]; then
	mkdir -p "$TEMP_PKG_DIR/lib/apk/packages/"
else
	mkdir -p "$TEMP_PKG_DIR/CONTROL/"
fi

cp -fpR "$PKG_DIR/htdocs"/* "$TEMP_PKG_DIR/www/"
cp -fpR "$PKG_DIR/root"/* "$TEMP_PKG_DIR/"
po2lmo "$PKG_DIR/po/zh_Hans/homeproxy.po" "$TEMP_PKG_DIR/usr/lib/lua/luci/i18n/homeproxy.zh-cn.lmo"

cat > "$TEMP_PKG_DIR/etc/uci-defaults/$PKG_NAME-i18n" <<-EOF
#!/bin/sh
uci set luci.languages.zh_cn='简体中文 (Simplified Chinese)'
uci commit luci
exit 0
EOF
chmod 0755 "$TEMP_PKG_DIR/etc/uci-defaults/$PKG_NAME-i18n"

cat > "$TEMP_PKG_DIR/lib/upgrade/keep.d/$PKG_NAME" <<-EOF
/etc/homeproxy/certs/
/etc/homeproxy/ruleset/
/etc/homeproxy/resources/direct_list.txt
/etc/homeproxy/resources/proxy_list.txt
EOF

if [ "$PKG_MGR" == "apk" ]; then
	find "$TEMP_PKG_DIR" -type f,l -printf '/%P\n' | sort > "$TEMP_PKG_DIR/lib/apk/packages/$PKG_NAME.list"
	echo "/etc/config/homeproxy" >> "$TEMP_PKG_DIR/lib/apk/packages/$PKG_NAME.conffiles"
	cat "$TEMP_PKG_DIR/lib/apk/packages/$PKG_NAME.conffiles" | while IFS= read -r file; do
		[ -f "$TEMP_PKG_DIR/$file" ] || continue
		sha256sum "$TEMP_PKG_DIR/$file" | sed "s,$TEMP_PKG_DIR/,," >> "$TEMP_PKG_DIR/lib/apk/packages/$PKG_NAME.conffiles_static"
	done

	refresh_luci='[ -n "${IPKG_INSTROOT}" ] || {
	for file in /etc/homeproxy/scripts/*.apk-new; do
		[ -e "$file" ] || continue
		target="${file%.apk-new}"
		mv -f "$file" "$target"
		chmod 0755 "$target" 2>/dev/null || true
	done

	(
	sleep 8
	rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null
	rm -rf /tmp/luci-modulecache/ 2>/dev/null
	/etc/init.d/rpcd restart 2>/dev/null || killall -HUP rpcd 2>/dev/null
	/etc/init.d/uhttpd restart 2>/dev/null || true
	) >/dev/null 2>&1 </dev/null &
	exit 0
}'

	echo -e '#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="'"$PKG_NAME"'"
add_group_and_user
default_postinst
'"${refresh_luci}" > "$TEMP_DIR/post-install"

	echo -e '#!/bin/sh
export PKG_UPGRADE=1
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="'"$PKG_NAME"'"
add_group_and_user
default_postinst
'"${refresh_luci}" > "$TEMP_DIR/post-upgrade"

	echo -e '#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="'"$PKG_NAME"'"
default_prerm' > "$TEMP_DIR/pre-deinstall"

	sign_args=()
	if [ -n "${APK_SIGN_KEY:-}" ]; then
		sign_args+=(--sign-key "$APK_SIGN_KEY")
	fi

	apk mkpkg \
		"${sign_args[@]}" \
		--info "name:$PKG_NAME" \
		--info "version:$PKG_VERSION" \
		--info "description:$PKG_DESCRIPTION" \
		--info "arch:noarch" \
		--info "origin:$PKG_ORIGIN" \
		--info "url:$PKG_URL" \
		--info "maintainer:$PKG_MAINTAINER" \
		--info "provides:$APK_PROVIDES_TEXT" \
		--info "replaces:$APK_REPLACES_TEXT" \
		--info "replaces-priority:10" \
		--script "post-install:$TEMP_DIR/post-install" \
		--script "post-upgrade:$TEMP_DIR/post-upgrade" \
		--script "pre-deinstall:$TEMP_DIR/pre-deinstall" \
		--info "depends:libc sing-box firewall4 kmod-nft-tproxy ucode-mod-digest ucode-mod-socket ucode-mod-uloop" \
		--files "$TEMP_PKG_DIR" \
		--output "$TEMP_DIR/${PKG_NAME}_${PKG_VERSION}.apk"

	mv "$TEMP_DIR/${PKG_NAME}_${PKG_VERSION}.apk" "$BASE_DIR/${PKG_NAME}_${PKG_VERSION}_all.apk"
else
	mkdir -p "$TEMP_PKG_DIR/CONTROL/"

	cat > "$TEMP_PKG_DIR/CONTROL/control" <<-EOF
		Package: $PKG_NAME
		Version: $PKG_VERSION
		Depends: libc, sing-box, firewall4, kmod-nft-tproxy, ucode-mod-digest, ucode-mod-socket, ucode-mod-uloop
		Provides: $IPK_PROVIDES_TEXT
		Replaces: $IPK_REPLACES_TEXT
		Conflicts: $IPK_CONFLICTS_TEXT
		Source: $PKG_URL
		SourceName: $PKG_NAME
		Section: luci
		SourceDateEpoch: $PKG_SOURCE_DATE_EPOCH
		Maintainer: $PKG_MAINTAINER
		Architecture: all
		Installed-Size: TO-BE-FILLED-BY-IPKG-BUILD
		Description:  $PKG_DESCRIPTION
	EOF
	chmod 0644 "$TEMP_PKG_DIR/CONTROL/control"

	echo -e "/etc/config/homeproxy" > "$TEMP_PKG_DIR/CONTROL/conffiles"

	echo -e '#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_postinst $0 $@' > "$TEMP_PKG_DIR/CONTROL/postinst"
	chmod 0755 "$TEMP_PKG_DIR/CONTROL/postinst"

	echo -e "[ -n "\${IPKG_INSTROOT}" ] || {
	(. /etc/uci-defaults/$PKG_NAME) && rm -f /etc/uci-defaults/$PKG_NAME
	rm -f /tmp/luci-indexcache
	rm -rf /tmp/luci-modulecache/
	exit 0
}" > "$TEMP_PKG_DIR/CONTROL/postinst-pkg"
	chmod 0755 "$TEMP_PKG_DIR/CONTROL/postinst-pkg"

	echo -e '#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_prerm $0 $@' > "$TEMP_PKG_DIR/CONTROL/prerm"
	chmod 0755 "$TEMP_PKG_DIR/CONTROL/prerm"

	ipkg-build -m "" "$TEMP_PKG_DIR" "$TEMP_DIR"

	mv "$TEMP_DIR/${PKG_NAME}_${PKG_VERSION}_all.ipk" "$BASE_DIR/${PKG_NAME}_${PKG_VERSION}_all.ipk"
fi

rm -rf "$TEMP_DIR"
