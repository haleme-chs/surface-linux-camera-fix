#!/bin/bash
# Build and install the Surface camera fixes.
# Safe to run again after a git pull or a PipeWire upgrade.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"

require_root
umask 022

if ! command -v apt-get >/dev/null 2>&1; then
	echo "This installer uses apt. It was written for Ubuntu and Debian." >&2
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive

pkg_dir="$ROOT/dkms/dw9719-ipu3"
VER=$(awk '/^Version:/{print $2; exit}' "$pkg_dir/packaging/control")
DKMS_VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$pkg_dir/dkms.conf")
POST_VER=$(sed -n 's/^VERSION=//p' "$pkg_dir/packaging/postinst")
PRE_VER=$(sed -n 's/^VERSION=//p' "$pkg_dir/packaging/prerm")
if [[ "$VER" != "$DKMS_VER" || "$VER" != "$POST_VER" || "$VER" != "$PRE_VER" ]]; then
	echo "Version mismatch: control=$VER dkms=$DKMS_VER postinst=$POST_VER prerm=$PRE_VER" >&2
	exit 1
fi
if ! grep -q "dw9719-ipu3/${VER}/build" "$pkg_dir/dkms.conf"; then
	echo "dkms.conf build path does not match version $VER" >&2
	exit 1
fi

echo "Installing build dependencies..."
apt-get install -y \
	build-essential \
	dkms \
	"linux-headers-$(uname -r)" \
	libcamera-dev \
	libcamera-ipa \
	libpipewire-0.3-dev \
	libspa-0.2-libcamera \
	pkg-config \
	sbsigntool \
	zstd

PW_VER=$(pkg-config --modversion libpipewire-0.3)
case "$PW_VER" in
	1.6.*) ;;
	*)
		echo "The camera plugin sources match PipeWire 1.6.2." >&2
		echo "This system has PipeWire ${PW_VER}. The build will still be attempted." >&2
		;;
esac

build=
stage=
deb=
cleanup() {
	if [[ -n "$build" ]]; then
		rm -rf "$build"
	fi
	if [[ -n "$stage" ]]; then
		rm -rf "$stage"
	fi
	if [[ -n "$deb" ]]; then
		rm -f "$deb"
	fi
}
trap cleanup EXIT

echo "Building the PipeWire camera plugin..."
build=$(mktemp -d)
cp -a "$ROOT/spa-libcamera/." "$build/"
make -C "$build" -j"$(nproc)"
plugin_so="$build/libspa-libcamera.so"
if [[ ! -s "$plugin_so" ]]; then
	echo "The plugin build did not produce libspa-libcamera.so" >&2
	exit 1
fi

echo "Building dw9719-ipu3-dkms ${VER}..."
stage=$(mktemp -d)
name=dw9719-ipu3
dest="$stage/usr/src/${name}-${VER}"
install -d "$dest" \
	"$stage/DEBIAN" \
	"$stage/usr/share/libcamera/ipa/ipu3" \
	"$stage/usr/share/doc/${name}-dkms" \
	"$stage/etc/kernel/postinst.d"
install -m 644 \
	"$pkg_dir/Makefile" \
	"$pkg_dir/dkms.conf" \
	"$pkg_dir/dw9719.c" \
	"$pkg_dir/ov8865.c" \
	"$dest/"
install -m 644 "$pkg_dir/ov8865.yaml" \
	"$stage/usr/share/libcamera/ipa/ipu3/ov8865.yaml"
install -m 644 "$pkg_dir/packaging/copyright" \
	"$stage/usr/share/doc/${name}-dkms/copyright"
install -m 644 "$pkg_dir/packaging/control" "$stage/DEBIAN/control"
install -m 755 "$pkg_dir/packaging/postinst" "$stage/DEBIAN/postinst"
install -m 755 "$pkg_dir/packaging/prerm" "$stage/DEBIAN/prerm"
install -m 755 "$ROOT/scripts/sign-ipu3-imgu.sh" \
	"$stage/etc/kernel/postinst.d/sign-ipu3-imgu"
install -m 644 "$ROOT/etc/surface-linux-camera-fix.conf" \
	"$stage/etc/surface-linux-camera-fix.conf"
printf '%s\n' /etc/surface-linux-camera-fix.conf > "$stage/DEBIAN/conffiles"

deb=$(mktemp --suffix=.deb)
chmod 755 "$stage"
dpkg-deb --root-owner-group -Zxz --build "$stage" "$deb"

echo "Installing the package. Camera drivers that are already loaded stay loaded."
dpkg -i "$deb"

plugin=$(plugin_path)
plugin_dir=$(dirname "$plugin")
if [[ ! -d "$plugin_dir" ]]; then
	echo "PipeWire libcamera plugin directory is missing: $plugin_dir" >&2
	exit 1
fi
if ! dpkg-divert --list "$plugin" | grep -F -q "$plugin"; then
	dpkg-divert --local --rename --divert "${plugin}.distro" --add "$plugin"
fi
install -m 644 "$plugin_so" "$plugin"
echo "Installed $plugin"
echo "The distribution plugin is kept as ${plugin}.distro"

need_reboot=0
for mod in dw9719 ov8865; do
	if [[ -r "/sys/module/${mod}/srcversion" ]]; then
		loaded=$(cat "/sys/module/${mod}/srcversion")
		ondisk=$(modinfo -F srcversion "$mod" 2>/dev/null || true)
		if [[ -n "$ondisk" && "$loaded" != "$ondisk" ]]; then
			echo "${mod} is loaded from an older build."
			need_reboot=1
		fi
	fi
done
if [[ "$need_reboot" -eq 1 ]]; then
	echo "Reboot when you can. The running camera drivers stay loaded until then."
fi

# Group membership is present when the graphical session starts. The
# session permission on /dev/media* is attached a moment later, and
# PipeWire does not retry if that first open is refused.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
	if ! id -nG "${SUDO_USER}" | tr ' ' '\n' | grep -qx video; then
		usermod -aG video "${SUDO_USER}"
		echo "Added ${SUDO_USER} to the video group. It takes effect at the next login."
	fi
else
	echo "Run this script with sudo from the desktop account so that account can be added to the video group." >&2
fi

restart_user_pipewire
echo "Done. Open the Camera app and check both cameras."
