# tbs5210-usb

Standalone out-of-tree Linux driver set for the **TBS5210 DTMB USB box**.
The device code is adapted from the TBS media tree
(<https://github.com/tbsdtv/linux_media>) and TBS's beta driver package,
trimmed here to only the modules this device needs and compiled against the
**running kernel's own `dvb-core`/`dvb-usb`**, without shipping an entire
v4l media tree.

Primary target: Debian / Raspberry Pi OS / **Armbian** **arm64**, kernel
**7.x**. The same sources build and load on **Fedora x86_64** for testing —
the DVB/USB stack is arch-neutral, so you can validate the driver without the
board. It also builds on 6.x within the range supported by the sources, and
cross-builds for arm64/armhf from an amd64 host.

## Hardware

- USB ID: `734c:5210`
- demodulator: **GX1503** (NationalChip, DTMB / GB20600-2006), i2c `0x30`
- tuner: **Rafael Micro R850**
- firmware: `dvb-usb-id5210.fw` (USB bridge), `dvb-demod-gx1503B.fw` (GX1503 demod)

## Modules

| module | source | role |
|---|---|---|
| `dvb-usb-tbs5210.ko` | `dvb-usb/tbs5210.c` | USB bridge device driver (links against the kernel's `dvb-usb`) |
| `gx1503.ko` | `frontends/gx1503.c` | DTMB demodulator, i2c driver, loaded on demand |
| `r850.ko` | `tuners/r850.c` | R850 tuner, exports `r850_attach` |

Only the USB device driver needs to bind; `r850` is pulled in as a symbol
dependency and `gx1503` is requested via `request_module("gx1503")`.

### Why the vendored `vendor/dvb-usb.h`?

`drivers/media/usb/dvb-usb/dvb-usb.h` is a driver-private header that the
distro header packages do **not** install, but the kernel exports
`dvb_usb_device_init()` / `dvb_usb_device_exit()`. We therefore vendor a
copy of that header (plus the `dvb-pll.h` it includes) under `vendor/`. It
defines `struct dvb_usb_device_properties`, which is passed *into* the
kernel's `dvb-usb` core, so **it must match the ABI of the running kernel's
`dvb-usb.ko`**. The committed copy tracks mainline `master`.

Refresh from kernel.org (default), from a tag/branch, or from a local kernel
source tree:

```sh
./refresh-headers.sh              # mainline master from kernel.org
./refresh-headers.sh v7.2         # a specific mainline tag/branch
./refresh-headers.sh /path/to/linux-kernel-source   # distro kernel tree
#   Debian : apt-get source linux   (or the matching linux-source-<ver>)
#   Armbian: the tree fetched by armbian/build, or a family repo
#            (e.g. https://github.com/armbian/linux-rockchip)
#   Fedora : see "Refreshing headers on Fedora" below
```

For a kernel that carries patches (e.g. Fedora), prefer the local-tree form:
the running `dvb-usb.ko` was built from that layout, not from mainline.

## Prerequisites

The build needs the headers that match `uname -r` exactly.

- Debian / Raspberry Pi OS:
  ```sh
  sudo apt-get install build-essential linux-headers-$(uname -r)
  ```
- Armbian:
  ```sh
  sudo apt-get install build-essential
  # install the headers that match the running kernel
  sudo armbian-config --cmd HEAD01
  # or the equivalent package: linux-headers-<branch>-<family>, e.g.
  #   sudo apt-get install linux-headers-current-rockchip64
  #   (derive the suffix: linux-headers-$(uname -r | cut -d- -f2-))
  ```
  The Makefile finds headers in `/lib/modules/$(uname -r)/build` or, if that
  symlink is absent, in `/usr/src/linux-headers-$(uname -r)`.
- Fedora / RHEL:
  ```sh
  sudo dnf install gcc make kernel-devel-$(uname -r) kernel-headers
  ```
  (`kernel-devel` must match the running kernel; not the newest one.)
- Arch:
  ```sh
  sudo pacman -S base-devel linux-headers
  ```

The kernel must provide `dvb-core`, `dvb-usb` and `i2c-mux`. Check:

```sh
modinfo dvb-usb >/dev/null && echo "dvb-usb present"
```

## Build and install

```sh
make -j$(nproc)
sudo make install
```

The three modules are written to `build/` (`build/dvb-usb-tbs5210.ko`,
`build/gx1503.ko`, `build/r850.ko`); the source tree stays clean. On older
kernels that don't support the external-module output directory (`MO=`) they
fall back in-tree. Use `make BUILD= ...` to always build in-tree (DKMS does
this).

Install the firmware (both blobs are required — the USB bridge firmware is
loaded by `dvb-usb-tbs5210`, the demod firmware by `gx1503`):

```sh
sudo make install-firmware          # copies both into /lib/firmware
# or:
sudo cp firmware/dvb-usb-id5210.fw firmware/dvb-demod-gx1503B.fw /lib/firmware/
```

then replug the box (or reboot).

### DKMS

```sh
sudo cp -r . /usr/src/tbs5210-1.0
sudo dkms add -m tbs5210 -v 1.0
sudo dkms build -m tbs5210 -v 1.0
sudo dkms install -m tbs5210 -v 1.0
```

This rebuilds automatically on kernel upgrades.

### Fedora notes

- **Install path/tools** are the same: `make`, `sudo make install`
  (`modules_install` → `/lib/modules/$(uname -r)/extra`), `depmod`.
- **Secure Boot / module signing.** Fedora signs in-tree modules and, with
  Secure Boot enabled, refuses unsigned ones:
  ```
  module verification failed: signature and/or required key missing
  ```
  Either disable Secure Boot, or sign and enroll a key (MOK). With DKMS,
  Fedora's `akmods`/`kmodgenca` signs automatically; with plain DKMS set a
  signing key in `/etc/dkms/framework.conf`:
  ```
  mok_signing_key="/var/lib/dkms/mok.key"
  mok_certificate="/var/lib/dkms/mok.pub"
  ```
  then enroll it once with `mokutil --import /var/lib/dkms/mok.pub`.
- **Refreshing headers on Fedora.** `kernel-devel` does not ship
  `drivers/media/.../dvb-usb.h`. Get the matching source (e.g.
  `dnf download --source kernel` + `rpm -Uvh` / `rpmbuild -bp`), then:
  ```sh
  ./refresh-headers.sh ~/rpmbuild/BUILD/kernel-*/linux-*
  ```
- Fedora's kernel is extensively patched, so if the ABI check fails after a
  kernel update, refresh the vendored `dvb-usb.h` as above and rebuild.

### Armbian notes

Armbian is Debian-based, so the normal flow works:

```sh
sudo apt-get install build-essential
sudo armbian-config --cmd HEAD01        # install matching kernel headers
make -j$(nproc)
sudo make install
sudo make install-firmware
```

- **No module signing.** ARM boards don't use UEFI Secure Boot, so unlike
  Fedora the modules load unsigned. Ignore the signing note under Fedora.
- **Headers.** Armbian packages headers per branch/family as
  `linux-headers-<branch>-<family>` (branch `current`/`edge`/`legacy`/`vendor`;
  family e.g. `rockchip64`, `sunxi64`, `meson64`, `rk35xx`). There is usually
  no `linux-headers-$(uname -r)` package. Install the matching one with
  `sudo armbian-config --cmd HEAD01`, or e.g.
  `sudo apt-get install linux-headers-current-rockchip64`. The Makefile falls
  back to `/usr/src/linux-headers-$(uname -r)` if
  `/lib/modules/$(uname -r)/build` is missing.
- **Patched BSP kernels.** Armbian kernels (`*-current-rockchip64`,
  `*-sunxi64`, `*-meson64`, ...) carry patches. If the driver loads but probe
  fails with an ABI/`dvb-usb` mismatch, refresh the vendored header from the
  matching Armbian kernel source, then rebuild:
  ```sh
  ./refresh-headers.sh /path/to/armbian/linux-<family>
  ```
  Sources come from `https://github.com/armbian/build` (the kernel tree it
  fetches) or the family repo, e.g. `armbian/linux-rockchip`.
- **DKMS on Armbian** works the same as Debian (see above); it re-signs
  nothing and rebuilds on kernel upgrades. Armbian ABI bumps across
  `current`/`edge` often need a DKMS rebuild or a header refresh.
- **Cross-build from an amd64 host** (headers for the target kernel required):
  ```sh
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
       KDIR=/path/to/target/linux-headers
  ```

## Verify

```sh
lsmod | grep -E 'tbs5210|gx1503|r850|dvb_usb'
ls -l /dev/dvb/adapter0/                 # frontend0 demux0 dvr0 net0
cat /sys/class/dvb/dvb0.frontend0/dev    # major:minor (DVB_MAJOR = 212)
dvb-fe-tool -a 0
dmesg | grep -i tbs5210
```

You should get one adapter. Note the frontend advertises `SYS_DVBT`
(DVB-T), so scan/tune with DVB-T tooling on 8 MHz muxes even though the
hardware is DTMB. Validate at the DVB API level before blaming any app:

```sh
dvbv5-scan -a 0 <channels.conf>
dvbv5-zap  -a 0 -c <channels.conf> -m
```

## Docker (Tvheadend)

Applications (Tvheadend, etc.) use `/dev/dvb/adapterN/*`, not the USB
device. **Load the driver and firmware on the host first**, then start the
container. `--device` takes a device node, not a directory, so
`--device=/dev/dvb` does not work. DVB has a fixed major
(`DVB_MAJOR = 212`), so the robust approach is a device-cgroup rule plus a
bind mount:

```sh
docker run -d --name tvheadend \
  --device-cgroup-rule='c 212:* rmw' \
  -v /dev/dvb:/dev/dvb \
  -v /path/to/config:/config \
  -e PUID=1000 -e PGID=1000 \
  lscr.io/linuxserver/tvheadend:latest
```

Or pass each node explicitly (they must exist before the container starts):

```sh
docker run -d --name tvheadend \
  --device=/dev/dvb/adapter0/frontend0 \
  --device=/dev/dvb/adapter0/demux0 \
  --device=/dev/dvb/adapter0/dvr0 \
  -v /path/to/config:/config \
  lscr.io/linuxserver/tvheadend:latest
```

docker-compose:

```yaml
services:
  tvheadend:
    image: lscr.io/linuxserver/tvheadend:latest
    device_cgroup_rules:
      - 'c 212:* rmw'
    volumes:
      - /dev/dvb:/dev/dvb
      - ./config:/config
    environment:
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

Notes:

- Do **not** pass `/lib/firmware` or the `.ko` into the container — the
  host kernel owns the device and loads the firmware.
- The container user (`PUID`/`PGID`) needs read/write on the nodes. Give
  them group `video` with a udev rule:
  ```
  # /etc/udev/rules.d/90-dvb.rules
  KERNEL=="dvb*", SUBSYSTEM=="dvb", GROUP="video", MODE="0660"
  ```
- If you replug the box, prefer the bind-mount form; explicit `--device`
  mappings can go stale when the host recreates the nodes.
- Confirm inside the container: `docker exec tvheadend ls -l /dev/dvb/`.
- In Tvheadend: **Configuration → DVB Inputs → TV adapters**; the adapter
  shows up as **DVB-T** (see the `SYS_DVBT` delsys note above) — add a
  DVB-T network and the DTMB mux frequencies manually.

## Notes

- No TBS-private ioctls are used by this stack (no `DTV_MODCODE`,
  `FE_ECP3FW_*`, `VIDIOC_TBS_*`), so **no core/uapi patches are needed** —
  this is why the minimal approach works for this box.
- `gx1503.c` already guards the i2c `remove()` signature change with
  `LINUX_VERSION_CODE`, so 6.1+ is handled.
- Mainline 7.x already provides `SYS_DTMB` and `FEC_77_90`.

## Provenance

The driver sources are **adapted from TBS**: the full media tree at
<https://github.com/tbsdtv/linux_media> and TBS's beta driver package
`tbsdvb_v1014` (the 6.8–7.0 package fetched by `drv-tbs.sh`). They are
trimmed here to the TBS5210 stack and built against the distro kernel's
own `dvb-core`/`dvb-usb` instead of shipping the TBS media tree.

Note: TBS5210 is **not** in the `linux_media` `latest` branch — it only
appears in the beta package.

### Differences from the TBS sources

The driver is no longer identical to TBS's. Every change below is a
separate commit on `main`; the register tables are the vendor's unless
stated.

| Area | Change | Why | Behaviour |
|---|---|---|---|
| `gx1503` | `DVBFE_ALGO_HW` + `tune()` instead of dvb-core software zigzag | dvb-core re-tuned at f, f±step on any lock loss; each `set_frontend()` hard-resets the demod and restarts acquisition | An outage lasts as long as the disturbance plus one re-acquisition, instead of a retune loop |
| `gx1503` | **Demod MCU halted once locked** (`mcu_halt`, default on) | The firmware blob is an 8051 supervisor that periodically switches the channel estimator to a short "fast" profile; on a multipath channel that excursion collapses SNR and drops sync | The steady profile is held; the MCU is restarted for every tune and if lock stays lost. `mcu_halt=0` restores the vendor behaviour |
| `gx1503` | `FE_CAN_RECOVER` advertised | Matches the above | Informational |
| `gx1503` | CNR reported in millidB (`SNR*1000`, was `*250`) | DVBv5 `FE_SCALE_DECIBEL` is 0.001 dB | Applications reading the decibel statistic see the real value |
| `gx1503` | Guard-interval SNR offset kept fractional | `int snr_mod[] = {2.6, 0, 2.2}` truncated to `{2, 0, 2}` | Reported SNR follows the vendor formula |
| `gx1503` | `delivery_system` no longer overwritten with `SYS_DTMB` | `ops.delsys` is `{SYS_DVBT}`; re-setting DTMB failed with `-EINVAL` | Property round-trips work; tuning unchanged |
| `gx1503` | Firmware upload checks every write | Errors were discarded and `fw_loaded`/`active` set anyway | A failed upload now fails `init()` instead of running corrupt microcode |
| `gx1503` | `cfg_int_parm = 8*128/BW` (was `8/BW*128`) | Integer division gave 128 for every bandwidth | 6/7 MHz get 170/146; 8 MHz unchanged (only 8 MHz exercised) |
| `gx1503` | `imp_thres` module parameter (reg 0xC5) | Tuning surface for the impulse-noise threshold | No change unless set |
| `r850` | 15 module parameters for the DTMB AGC table (`force_pulse`, `nat_cain`, `rf_gain_limit`, `mixer_gain_limit`, `lna_top`, `rf_top`, `mixer_top`, `dis_mode`, `agc_clk`, `loop_through`, `pulse_hys`, `lna_dis`, `na_pwr_det`, `nrb_bw_hpf`, `img_gain`) | Lets a different installation be measured instead of guessed at | No change unless set; defaults are the vendor values |
| `r850` | `priv` freed when the attach-time register read fails | Leak | None in normal operation |
| `r850` | `Lna_Acc_Gain_offset[]` index clamped | Out-of-bounds read below 50 MHz / above 905 MHz | None in the 100–858 MHz range |
| `r850` | `r850_wrm()` fixed buffer instead of VLA; helpers `static` | Kernel coding rules | None |
| `tbs5210` | Module reference on `gx1503` released at disconnect | `try_module_get()` was never balanced (cleanup was `#if 0`) | `gx1503` can be unloaded; unplug/replug no longer leaks |
| `tbs5210` | I2C bridge propagates USB errors, short reads → `-EREMOTEIO`, unknown addresses → `-EOPNOTSUPP` | Every error was reported as success and an uninitialised buffer copied to the caller | Failed transfers now fail; demod/tuner error paths become reachable |
| `tbs5210` | I2C direction from `I2C_M_RD` instead of `flags == 0` | i2c-dev messages carry `I2C_M_DMA_SAFE`, so every userspace write was executed as a read | `/dev/i2c-N` writes work; kernel-side traffic unchanged |
| `tbs5210` | I2C message length bounds (0 and > 58 bytes rejected) | Stack buffer overrun | None for the demod/tuner |
| `tbs5210` | Firmware loader uses the blob passed by dvb-usb, `-ENOMEM` before touching the device, last chunk clamped | Blob requested twice and leaked; OOM returned success with the CPU halted; fixed 64-byte chunks read past the buffer | Same upload sequence; no leak |
| `tbs5210` | Orphan demod i2c client unregistered if `gx1503` does not bind | Its `platform_data` pointed at a dead stack frame | A later `modprobe gx1503` no longer writes through it |
| `firmware/` | `dvb-demod-gx1503B.fw` tracked | TBS package shipped only the bridge blob | Frontend activates |
| build | Kbuild/DKMS against distro `dvb-core`/`dvb-usb`, vendored `vendor/dvb-usb.h` | No TBS media tree | Same kernel APIs |

Not changed from TBS: every R850 and GX1503 register table and init
sequence, the I2C protocol, the firmware blobs, `SYS_DVBT` as the
advertised delivery system.

### Reverse engineering of the demod firmware

NationalChip publishes no datasheet or register map for the GX1503B, and
TBS ships the demod blob without documentation. To understand the
periodic sync loss, the blob was disassembled (it is an SDCC-compiled
8051 program, not DSP microcode) and its register writes were observed
live through the bridge's I2C adapter. The `mcu_halt` change and the
register semantics it relies on (`0xF7` bit 4 as the MCU run bit,
`0x99` as the profile indicator) come from that analysis, not from any
specification. They were validated on one TBS5210 in one installation;
there is **no guarantee** they hold on other units, firmware revisions
or signals. `mcu_halt=0` restores the vendor behaviour if in doubt.

## License

**GPL-2.0.** This follows the Linux kernel: the drivers are adapted from
TBS's GPL-2.0 media sources and link against the kernel's GPL-only DVB/USB
core (GPL-only exported symbols), so the modules must be GPL-2.0. Each
source file carries an `SPDX-License-Identifier: GPL-2.0` tag and the
vendored headers are kernel GPL-2.0 headers. Full text in `COPYING`.
