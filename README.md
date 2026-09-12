# tbs5210-usb

Standalone out-of-tree Linux driver set for the **TBS5210 DTMB USB box**.
The device code is adapted from the TBS media tree
(<https://github.com/tbsdtv/linux_media>) and TBS's beta driver package,
trimmed here to only the modules this device needs and compiled against the
**running kernel's own `dvb-core`/`dvb-usb`**, without shipping an entire
v4l media tree.

Primary target: Debian / Raspberry Pi OS **arm64**, kernel **7.x**. The same
sources build and load on **Fedora x86_64** for testing — the DVB/USB stack
is arch-neutral, so you can validate the driver without the Pi. It also
builds on 6.x within the range supported by the sources.

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

### Why the vendored `dvb-usb/dvb-usb.h`?

`drivers/media/usb/dvb-usb/dvb-usb.h` is a driver-private header that the
distro header packages do **not** install, but the kernel exports
`dvb_usb_device_init()` / `dvb_usb_device_exit()`. We therefore vendor a
copy of that header. It defines `struct dvb_usb_device_properties`, which
is passed *into* the kernel's `dvb-usb` core, so **it must match the ABI
of the running kernel's `dvb-usb.ko`**. The copy here is from mainline 7.3.

If your kernel carries patches that change this structure, refresh the
vendored headers from that kernel's source tree:

```sh
./refresh-headers.sh /path/to/linux-kernel-source
#   Debian : apt-get source linux   (or the matching linux-source-<ver>)
#   Fedora : see "Refreshing headers on Fedora" below
```

## Prerequisites

The build needs the headers that match `uname -r` exactly.

- Debian / Raspberry Pi OS:
  ```sh
  sudo apt-get install build-essential linux-headers-$(uname -r)
  ```
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

The two vendor firmware blobs are tracked in `firmware/`:
`dvb-usb-id5210.fw` (USB bridge) and `dvb-demod-gx1503B.fw` (GX1503 demod,
`sha256 e7d98dd185c37b24a1fd5793ab846a6c8ce26e163ab38bcb21a2efc5e9bacfca`).
`gx1503_init()` requests the demod blob with `request_firmware()`; without it
in `/lib/firmware` the request fails and the frontend never becomes active.

## License

**GPL-2.0.** This follows the Linux kernel: the drivers are adapted from
TBS's GPL-2.0 media sources and link against the kernel's GPL-only DVB/USB
core (GPL-only exported symbols), so the modules must be GPL-2.0. Each
source file carries an `SPDX-License-Identifier: GPL-2.0` tag and the
vendored headers are kernel GPL-2.0 headers. Full text in `COPYING`.
