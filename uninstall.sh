#!/bin/bash
# Remove the Surface camera package and restore the distribution plugin.
# Loaded kernel modules stay resident until the next reboot.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"

require_root

plugin=$(plugin_path)
if dpkg-divert --list "$plugin" | grep -F -q "$plugin"; then
	rm -f "$plugin"
	dpkg-divert --local --rename --remove "$plugin"
	echo "Restored ${plugin}"
fi

if dpkg -s dw9719-ipu3-dkms >/dev/null 2>&1; then
	dpkg -r dw9719-ipu3-dkms
fi

restart_user_pipewire

cat <<'EOF'
The package is removed. Camera drivers that are already loaded stay loaded.
Reboot to use the distribution modules.

/etc/surface-linux-camera-fix.conf is left in place. Remove it with:
  sudo dpkg --purge dw9719-ipu3-dkms
EOF
