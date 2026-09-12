#!/bin/sh
# Refresh the vendored driver-private DVB headers.
#
# dvb-usb.h / dvb-pll.h are kernel-private headers that linux-headers /
# kernel-devel do not ship. dvb-usb.h defines structs that are passed into
# the kernel's dvb-usb.ko, so the vendored layout MUST match the ABI of the
# target kernel - not necessarily mainline.
#
# usage:
#   ./refresh-headers.sh                 fetch mainline master from kernel.org
#   ./refresh-headers.sh <REF>           fetch tag/branch <REF> (e.g. v6.12)
#   ./refresh-headers.sh <kernel-src>    copy from a local kernel source tree
#
# For a distro kernel that carries patches, prefer the local-tree form (its
# layout is what the running dvb-usb.ko was built with). Mainline REFs are a
# convenience for unpatched kernels.
set -e

DEST="vendor"
BASE="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain"
DVB_USB="drivers/media/usb/dvb-usb/dvb-usb.h"
DVB_PLL="drivers/media/dvb-frontends/dvb-pll.h"

arg="${1:-}"

fetch() { # url dest
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$1" -o "$2"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO "$2" "$1"
	else
		echo "need curl or wget" >&2
		exit 1
	fi
}

mkdir -p "$DEST"

if [ -n "$arg" ] && [ -d "$arg" ]; then
	test -f "$arg/$DVB_USB" || {
		echo "not a kernel source tree: $arg" >&2; exit 1; }
	cp "$arg/$DVB_USB" "$DEST/dvb-usb.h"
	cp "$arg/$DVB_PLL" "$DEST/dvb-pll.h"
	echo "refreshed $DEST/dvb-usb.h and $DEST/dvb-pll.h from $arg"
elif [ -n "$arg" ] && [ -e "$arg" ]; then
	echo "not a kernel source tree: $arg" >&2
	exit 1
else
	if [ -n "$arg" ]; then
		query="?h=$arg"
		label="kernel.org $arg"
	else
		query=""
		label="kernel.org master"
	fi
	fetch "$BASE/$DVB_USB$query" "$DEST/dvb-usb.h"
	fetch "$BASE/$DVB_PLL$query" "$DEST/dvb-pll.h"
	echo "refreshed $DEST/dvb-usb.h and $DEST/dvb-pll.h from $label"
fi
