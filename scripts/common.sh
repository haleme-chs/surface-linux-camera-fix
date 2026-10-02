#!/bin/bash
# Helpers shared by install.sh and uninstall.sh.
# SPDX-License-Identifier: GPL-3.0-only

require_root() {
	if [[ "$(id -u)" -ne 0 ]]; then
		echo "Run as root: sudo bash $0" >&2
		exit 1
	fi
}

plugin_path() {
	local multiarch
	multiarch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
	printf '%s\n' "/usr/lib/${multiarch}/spa-0.2/libcamera/libspa-libcamera.so"
}

restart_user_pipewire() {
	local user uid
	user=${SUDO_USER:-}
	if [[ -z "$user" || "$user" == root ]]; then
		echo "No desktop user in SUDO_USER."
		echo "From the logged-in session, run:"
		echo "  systemctl --user try-restart pipewire pipewire-pulse wireplumber"
		return 0
	fi
	uid=$(id -u "$user")
	if [[ ! -S "/run/user/${uid}/bus" ]]; then
		echo "No session bus for ${user}. The plugin loads the next time PipeWire starts."
		return 0
	fi
	echo "Restarting PipeWire for ${user} so the camera plugin is reloaded."
	sudo -u "$user" env \
		XDG_RUNTIME_DIR="/run/user/${uid}" \
		DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
		systemctl --user try-restart pipewire.service pipewire-pulse.service wireplumber.service
}
