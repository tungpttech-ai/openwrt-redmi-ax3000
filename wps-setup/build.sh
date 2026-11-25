#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if [[ $# != 3 ]]; then
	printf 'Usage: %s IMAGEBUILDER_DIR STOCK_FACTORY_UBI OUTPUT_DIR\n' "$0" >&2
	exit 2
fi
here=$(cd -- "$(dirname -- "$0")" && pwd)
tools=$(cd -- "$1/staging_dir/host/bin" && pwd)
stock=$(realpath -- "$2")
mkdir -m 700 -p -- "$3"
output=$(cd -- "$3" && pwd)
read -r checksum _ < <(sha256sum -- "$stock")
case "$checksum" in
	8ec4fd5b5c2ad4d7f802ad57f356811216b75f032103c7662879aca985be9f3e) profile=redmi_ax3000 ;;
	3c80088525adf1f6f992a2bf4dc3aaecb242278dff1c6bfd33ce689eed0d2e5d) profile=cmcc_rax3000q ;;
	*) printf 'Stock UBI does not match the supported stock release.\n' >&2; exit 2 ;;
esac

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
uv tool run --from ubi-reader==0.8.16 ubireader_extract_images -o "$work/volumes" "$stock"
kernel=("$work/volumes/"*/*_vol-kernel.ubifs)
rootfs=("$work/volumes/"*/*_vol-rootfs.ubifs)
[[ ${#kernel[@]} == 1 && -s ${kernel[0]} && ${#rootfs[@]} == 1 && -s ${rootfs[0]} ]]
root="$work/root"
"$tools/unsquashfs4" -no-progress -processors 2 -d "$root" "${rootfs[0]}"
cp -R -- "$here/root/." "$root/"
chmod 755 "$root/etc/wps-setup/button" "$root/etc/uci-defaults/99-wps-setup"
chmod 600 "$root/etc/wps-setup/hostapd.conf"
printf 'wpa_passphrase=%s\n' "$password" >> "$root/etc/wps-setup/hostapd.conf"
unset password

if [[ $profile == cmcc_rax3000q ]]; then
	# GPIO 23 is a reset event in this profile. Preserve the long-press reset.
	awk '/echo "REBOOT"/ { print "\t\t/etc/wps-setup/button tap"; getline; getline; n++; next }
	     { print } END { if (n != 1) exit 1 }' "$root/etc/rc.button/reset" > "$work/reset"
	install -m 755 "$work/reset" "$root/etc/rc.button/reset"
else
	cat > "$root/etc/rc.button/wps" <<'EOF'
#!/bin/sh
[ "$ACTION" = released ] || exit 0
exec /etc/wps-setup/button tap
EOF
	chmod 755 "$root/etc/rc.button/wps"
fi

console=()
# The release has one device node. Unprivileged extraction cannot recreate it.
[[ -c $root/dev/console ]] || console=(-p '/dev/console c 600 0 0 5 1')
"$tools/mksquashfs4" "$root" "$work/root.squashfs" -nopad -noappend -root-owned -no-xattrs \
	-comp xz -Xpreset 9 -Xe -Xlc 0 -Xlp 2 -Xpb 2 -Xbcj arm -b 262144 -processors 1 \
	"${console[@]}" -no-progress
TOPDIR="$here/.." PATH="$tools:$PATH" sh "$here/../scripts/ubinize-image.sh" \
	--kernel "${kernel[0]}" "$work/root.squashfs" "$work/setup.ubi" -p 128KiB -m 2048
install -m 600 "$work/setup.ubi" "$output/openwrt-ipq50xx-arm-$profile-wps-setup-nand-factory.ubi"
