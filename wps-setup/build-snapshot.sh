#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if [[ $# != 2 ]]; then
	printf 'Usage: %s STOCK_SYSUPGRADE_BIN OUTPUT_FACTORY_UBI\n' "$0" >&2
	exit 2
fi
here=$(cd -- "$(dirname -- "$0")" && pwd)
stock=$(realpath -- "$1")
output=$(realpath -m -- "$2")
read -r checksum _ < <(sha256sum -- "$stock")
if [[ $checksum != 4519f6df80d26454a5d98ac6750c9e09098ba6dad9bf6da3f3afe753fe7b44ef ]]; then
	printf 'Expected the CR8806 image from ipq50xx-2026.11.24.\n' >&2
	exit 2
fi

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

work=$(mktemp -d)
trap 'rm -r -- "$work"' EXIT
umask 022
tar -xf "$stock" -C "$work"
image="$work/sysupgrade-xiaomi_cr8806"
root="$work/root"
# Extract regular files unprivileged and recreate the release's single device node below.
unsquashfs -strict-errors -no-progress -processors 2 -d "$root" -excludes "$image/root" dev/console

apk=(qemu-aarch64 -E "LD_LIBRARY_PATH=$root/lib:$root/usr/lib" -L "$root" "$root/usr/bin/apk" --root "$root")
"${apk[@]}" update
"${apk[@]}" --no-scripts add 'luci-ssl=26.328.33115~9ece310'

cp -R -- "$here/root/." "$root/"
chmod 755 "$root/etc/wps-setup/button" "$root/etc/uci-defaults/99-wps-setup"
chmod 600 "$root/etc/wps-setup/hostapd.conf"
printf 'wpa_passphrase=%s\n' "$password" >> "$root/etc/wps-setup/hostapd.conf"
unset password
install -m 755 "$here/snapshot-wps-hook" "$root/etc/rc.wps/10-setup"
ln -sf ../init.d/rpcd "$root/etc/rc.d/S12rpcd"
ln -sf ../init.d/uhttpd "$root/etc/rc.d/S50uhttpd"

mksquashfs "$root" "$work/root.squashfs" -nopad -noappend -all-root -no-xattrs \
	-comp xz -b 262144 -processors 2 -p '/dev/console c 600 0 0 5 1' -no-progress
TOPDIR="$here/.." sh "$here/../scripts/ubinize-image.sh" \
	--kernel "$image/kernel" "$work/root.squashfs" "$work/setup.ubi" -p 128KiB -m 2048
install -m 600 "$work/setup.ubi" "$output"
