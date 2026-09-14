# Build wrapper for the TBS5210 driver set.
#
# Works on any distro whose kernel headers are reachable via
# /lib/modules/$(uname -r)/build or /usr/src/linux-headers-$(uname -r):
#   - Debian / Raspberry Pi OS / Armbian: apt install linux-headers-$(uname -r)
#   - Fedora/RHEL:                        dnf install kernel-devel kernel-headers
#   - Arch:                               pacman -S linux-headers
#
# Override the kernel build dir if needed:
#   make KDIR=/usr/src/linux-headers-$(uname -r)
#
# Cross-compile (e.g. build arm64 on an amd64 host):
#   make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
#        KDIR=/path/to/target/linux-headers
#   make ARCH=armhf CROSS_COMPILE=arm-linux-gnueabihf- ...
#
# Build artifacts go to ./build, keeping the source tree clean. On kernels
# that support the external-module output directory this uses MO=; on older
# kernels MO= is ignored and the build falls back in-tree. Set BUILD= to
# force an in-tree build (used by DKMS):
#   make BUILD=

KVER  ?= $(shell uname -r)
# Kernel build dir. Try, in order: the modules build symlink, the exact
# versioned headers dir, then any headers dir for this kernel release
# (Armbian may name the tree with a branch/family suffix).
KDIR  ?= $(firstword $(wildcard /lib/modules/$(KVER)/build) \
                    $(wildcard /usr/src/linux-headers-$(KVER)) \
                    $(wildcard /usr/src/linux-headers-$(KVER)*))
BUILD ?= $(CURDIR)/build

FIRMWARE_DIR ?= /lib/firmware

# Cross-build arguments are passed only when the caller sets them, so a
# native build on the target (x86, arm64, armhf) keeps working untouched.
KBUILD_ARGS  := $(if $(ARCH),ARCH=$(ARCH) )$(if $(CROSS_COMPILE),CROSS_COMPILE=$(CROSS_COMPILE))
MODPATH_ARGS := $(if $(INSTALL_MOD_PATH),INSTALL_MOD_PATH=$(INSTALL_MOD_PATH))

default: check
	@if [ -n "$(BUILD)" ]; then mkdir -p "$(BUILD)"; fi
	$(MAKE) -C $(KDIR) M=$(CURDIR) MO=$(BUILD) $(KBUILD_ARGS) modules

check:
	@test -d "$(KDIR)" || { \
		echo "ERROR: kernel build dir not found (KVER=$(KVER))."; \
		echo "  searched : /lib/modules/$(KVER)/build"; \
		echo "             /usr/src/linux-headers-$(KVER)"; \
		echo "  present  : $$(ls -d /usr/src/linux-headers-* 2>/dev/null | tr '\n' ' ')"; \
		echo "  note     : if the headers are for a newer kernel than $(KVER),"; \
		echo "             boot that kernel (or install matching headers) first"; \
		echo "  Debian/Pi: sudo apt install linux-headers-$(KVER)"; \
		echo "  Armbian  : sudo armbian-config --cmd HEAD01"; \
		echo "             (headers are linux-headers-<branch>-<family>)"; \
		echo "  Fedora   : sudo dnf install kernel-devel-$(KVER) kernel-headers"; \
		echo "  or       : make KDIR=/usr/src/linux-headers-$(KVER)"; \
		exit 1; }
	@hver=$$(cat "$(KDIR)/include/config/kernel.release" 2>/dev/null); \
	[ -n "$$hver" ] || hver=$$(sed -n 's/^#define UTS_RELEASE "\(.*\)"/\1/p' \
		"$(KDIR)/include/generated/utsrelease.h" 2>/dev/null); \
	if [ -n "$$hver" ] && [ "$$hver" != "$(KVER)" ]; then \
		echo "WARNING: kernel headers target '$$hver' but the running kernel is '$(KVER)'."; \
		echo "         Modules will get vermagic '$$hver' and will NOT load on $(KVER)."; \
		echo "         Upgrade + reboot so the kernel matches the headers, or install"; \
		echo "         matching headers (make KVER=$$hver to build for the header kernel)."; \
	fi

install: default
	$(MAKE) -C $(KDIR) M=$(CURDIR) MO=$(BUILD) $(KBUILD_ARGS) $(MODPATH_ARGS) modules_install
	@if [ -n "$(INSTALL_MOD_PATH)" ]; then depmod -b $(INSTALL_MOD_PATH) $(KVER); else depmod -a $(KVER); fi
	@echo "Installed. Armbian/Debian/Pi do not enforce module signatures."
	@echo "On Fedora + Secure Boot the module must be signed (mokutil/sign-file/akmods)."

install-firmware:
	install -d $(FIRMWARE_DIR)
	install -m 644 firmware/dvb-usb-id5210.fw firmware/dvb-demod-gx1503B.fw firmware/dvb-demod-gx1503B-supervisor.fw $(FIRMWARE_DIR)/

clean:
	@if [ -n "$(BUILD)" ] && [ -d "$(BUILD)" ]; then \
		$(MAKE) -C $(KDIR) M=$(CURDIR) MO=$(BUILD) clean; \
		rm -rf "$(BUILD)"; \
	else \
		$(MAKE) -C $(KDIR) M=$(CURDIR) clean; \
	fi

.PHONY: default check install install-firmware clean
