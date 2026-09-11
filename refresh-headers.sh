#!/bin/sh
# Refresh the vendored driver-private DVB USB headers from a kernel source
# tree, so the vendored struct layouts match the target kernel's dvb-usb.ko.
#
# usage: ./refresh-headers.sh /path/to/linux-kernel-source
set -e

SRC="${1:?usage: $0 /path/to/linux-kernel-source}"

test -f "$SRC/drivers/media/usb/dvb-usb/dvb-usb.h" || {
	echo "not a kernel source tree: $SRC" >&2; exit 1; }

cp "$SRC/drivers/media/usb/dvb-usb/dvb-usb.h" dvb-usb/dvb-usb.h
cp "$SRC/drivers/media/dvb-frontends/dvb-pll.h" dvb-usb/dvb-pll.h
echo "refreshed dvb-usb/dvb-usb.h and dvb-usb/dvb-pll.h from $SRC"
