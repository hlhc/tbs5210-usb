# AGENTS.md

Out-of-tree Linux driver for the **TBS5210** DTMB USB box (USB `734c:5210`,
GX1503 demod + R850 tuner). Built against the distro kernel's own
`dvb-core`/`dvb-usb`; no v4l media tree is shipped. `README.md` is the
operator guide; this file is the agent-onboarding summary.

## Environment constraints
- This workspace runs on macOS: **you cannot compile kernel modules here.**
  Compile on Linux with headers matching `uname -r`.
- `.ko` are version-locked (vermagic). Never build for one kernel and deploy
  to another; rebuild per kernel (or via DKMS).

## Build & install (on Linux)
- `make -j$(nproc)` → `build/dvb-usb-tbs5210.ko`, `build/gx1503.ko`,
  `build/r850.ko` (Kbuild `MO=`; source tree stays clean). `make BUILD= ...`
  builds in-tree; DKMS does this so its module discovery still works.
- `sudo make install` (installs to `/lib/modules/$(uname -r)/extra`, runs `depmod`).
- `sudo cp firmware/dvb-usb-id5210.fw firmware/dvb-demod-gx1503B.fw /lib/firmware/`.
- Override the kernel build dir with `KDIR=`; the `check` target validates it
  and prints distro-specific install hints.

## Module wiring
- `dvb-usb-tbs5210` binds USB, loads firmware, builds the adapter; links
  against the kernel's `dvb-usb` (`dvb_usb_device_init`).
- `r850` exports `r850_attach` (GPL) and is auto-loaded as a symbol dependency.
- `gx1503` is an i2c driver loaded on demand via `request_module("gx1503")`.
- All three are required. Only `dvb-usb-tbs5210` is user-loaded.

## Critical: vendored private headers
- `vendor/dvb-usb.h` and `vendor/dvb-pll.h` are kernel-private headers that
  `linux-headers`/`kernel-devel` do not ship. `dvb-usb.h` defines structs
  passed into the kernel's `dvb-usb.ko`, so its layout must match the running
  kernel.
- Do **not** hand-edit them. Refresh with `./refresh-headers.sh` (kernel.org
  master), `./refresh-headers.sh <tag>` (a mainline ref), or
  `./refresh-headers.sh <kernel-src>` (a local distro kernel tree).
- Do **not** copy TBS's own `dvb-usb.h` in: it has extra fields (`fe2`) that
  break the ABI against mainline.

## Provenance & licensing
- Adapted from TBS (`tbsdvb_v1014` beta package / `github.com/tbsdtv/linux_media`).
  TBS5210 is **not** in `linux_media` `latest`/`gse`.
- Do not introduce TBS-private core changes (no `DTV_MODCODE`, `FE_ECP3FW_*`,
  `VIDIOC_TBS_*`); this device uses only stable mainline APIs.
- License **GPL-2.0**, kernel-style, SPDX on every file; keep
  `MODULE_LICENSE("GPL")`. `firmware/dvb-usb-id5210.fw` and
  `firmware/dvb-demod-gx1503B.fw` are required vendor blobs — tracked on
  purpose, don't delete.
- `gx1503.c`/`r850.c` contain `LINUX_VERSION_CODE` guards for kernel API
  changes (probe/remove/i2c-mux). Keep them.

## Validation (no test suite)
- `lsmod | grep -E 'tbs5210|gx1503|r850'`
- `ls -l /dev/dvb/adapter0/` (frontend0 demux0 dvr0 net0), `dmesg | grep -i tbs5210`
- Tuning: `dvb-fe-tool -a 0`, `dvbv5-scan`, `dvbv5-zap`. The frontend
  advertises `SYS_DVBT` (not `SYS_DTMB`) despite being DTMB hardware — scan as
  DVB-T on 8 MHz muxes.
- Docker/Tvheadend uses `/dev/dvb` (DVB major 212); see README "Docker (Tvheadend)".

## Conventions
- Don't commit build artifacts (`*.ko`, `*.o`, `Module.symvers`, …);
  `.gitignore` covers them.
- This directory is its own git repo (branch `main`, remote `hlhc/tbs5210-usb`).
  The parent workspace is not a repo.
