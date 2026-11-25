#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if [[ $# != 3 || ( $2 != redmi_ax3000 && $2 != cmcc_rax3000q ) ]]; then
	printf 'Usage: %s IMAGEBUILDER_DIR {redmi_ax3000|cmcc_rax3000q} OUTPUT_DIR\n' "$0" >&2
	exit 2
fi
here=$(cd -- "$(dirname -- "$0")" && pwd)
builder=$(cd -- "$1" && pwd)
mkdir -p -- "$3"
output=$(cd -- "$3" && pwd)

if [[ -n ${WPS_SETUP_PASSWORD_FILE:-} ]]; then
	password=$(cat -- "$WPS_SETUP_PASSWORD_FILE")
else
	IFS= read -rs -p 'Setup Wi-Fi password (8-63 printable ASCII characters): ' password
	printf '\n' >&2
fi
if [[ ! $password =~ ^[[:print:]]{8,63}$ ]]; then
	printf 'Invalid WPA2 password.\n' >&2
	exit 2
fi

overlay=$(mktemp -d)
trap 'rm -r -- "$overlay"' EXIT
umask 022
cp -R -- "$here/root/." "$overlay/"
chmod 755 "$overlay/etc/wps-setup/button" "$overlay/etc/uci-defaults/99-wps-setup"
chmod 600 "$overlay/etc/wps-setup/hostapd.conf"
printf 'wpa_passphrase=%s\n' "$password" >> "$overlay/etc/wps-setup/hostapd.conf"
unset password

mkdir "$overlay/etc/rc.button"
if [[ $2 == cmcc_rax3000q ]]; then
	# GPIO 23 is a reset event in this profile. Preserve the long-press reset.
	awk '/echo "REBOOT"/ { print "\t\t/etc/wps-setup/button tap"; getline; getline; n++; next }
	     { print } END { if (n != 1) exit 1 }' \
		"$here/../package/base-files/files/etc/rc.button/reset" > "$overlay/etc/rc.button/reset"
	chmod 755 "$overlay/etc/rc.button/reset"
else
	cat > "$overlay/etc/rc.button/wps" <<'EOF'
#!/bin/sh
[ "$ACTION" = released ] || exit 0
exec /etc/wps-setup/button tap
EOF
	chmod 755 "$overlay/etc/rc.button/wps"
fi

make -C "$builder" image PROFILE="$2" FILES="$overlay" BIN_DIR="$output" PACKAGES='flock iw luci'
