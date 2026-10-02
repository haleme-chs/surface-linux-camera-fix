#!/bin/bash
# Secure Boot rejects Ubuntu's unsigned ipu3-imgu module. Sign the on-disk
# copy with the machine owner key. As a kernel postinst hook, $1 is the
# new kernel version.
#
# A missing key is not an error. On Ubuntu, DKMS creates
# /var/lib/shim-signed/mok/ during its own install, and the key is trusted
# only after MokManager enrolls it at the next reboot. This hook must exit 0
# so a kernel upgrade is never blocked.
# SPDX-License-Identifier: GPL-3.0-only
set -u

KVER="${1:-$(uname -r)}"

KMODSIGN=$(command -v kmodsign || true)
if [[ -z "$KMODSIGN" ]]; then
	echo "sign-ipu3-imgu: kmodsign is not installed, skipping" >&2
	exit 0
fi

KEY=""
CERT=""
pairs=(
	"/var/lib/shim-signed/mok/MOK.priv|/var/lib/shim-signed/mok/MOK.der"
	"/var/lib/dkms/mok.key|/var/lib/dkms/mok.pub"
)
for pair in "${pairs[@]}"; do
	candidate_key=${pair%%|*}
	candidate_cert=${pair#*|}
	if [[ -f "$candidate_key" && -f "$candidate_cert" ]]; then
		KEY=$candidate_key
		CERT=$candidate_cert
		break
	fi
done

if [[ -z "$KEY" ]]; then
	echo "sign-ipu3-imgu: no local module key, skipping" >&2
	exit 0
fi

shopt -s nullglob
mods=(/lib/modules/"$KVER"/kernel/drivers/staging/media/ipu3/ipu3-imgu.ko*)
if [[ ${#mods[@]} -eq 0 ]]; then
	exit 0
fi

for mod in "${mods[@]}"; do
	work=$(mktemp)
	case "$mod" in
	*.zst)
		if ! zstd -dc "$mod" > "$work"; then
			rm -f "$work"
			echo "sign-ipu3-imgu: could not decompress $mod" >&2
			exit 0
		fi
		;;
	*.xz)
		if ! xz -dc "$mod" > "$work"; then
			rm -f "$work"
			echo "sign-ipu3-imgu: could not decompress $mod" >&2
			exit 0
		fi
		;;
	*) cp "$mod" "$work" ;;
	esac

	if tail -c 40 "$work" | grep -q 'Module signature appended'; then
		rm -f "$work"
		continue
	fi

	if ! "$KMODSIGN" sha512 "$KEY" "$CERT" "$work"; then
		echo "sign-ipu3-imgu: failed to sign $mod" >&2
		rm -f "$work"
		exit 0
	fi

	case "$mod" in
	*.zst) zstd -19 -f -q -o "$mod" "$work" ;;
	*.xz) xz -c -9 "$work" > "$mod" ;;
	*) cp "$work" "$mod" ;;
	esac
	rm -f "$work"
	echo "sign-ipu3-imgu: signed $mod"
done

depmod -a "$KVER" || true
exit 0
