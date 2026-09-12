# Build wrapper for the TBS5210 driver set.
#
# Works on any distro whose kernel headers are reachable via
# /lib/modules/$(uname -r)/build:
#   - Debian/Raspberry Pi OS: apt install linux-headers-$(uname -r)
#   - Fedora/RHEL:            dnf install kernel-devel kernel-headers
#   - Arch:                   pacman -S linux-headers
#
# Override the kernel build dir if needed:
#   make KDIR=/usr/src/kernels/$(uname -r)
#
# Build artifacts go to ./build, keeping the source tree clean. On kernels
# that support the external-module output directory this uses MO=; on older
# kernels MO= is ignored and the build falls back in-tree. Set BUILD= to
# force an in-tree build (used by DKMS):
#   make BUILD=

KVER  ?= $(shell uname -r)
KDIR  ?= /lib/modules/$(KVER)/build
BUILD ?= $(CURDIR)/build

default: check
	@if [ -n "$(BUILD)" ]; then mkdir -p "$(BUILD)"; fi
	$(MAKE) -C $(KDIR) M=$(CURDIR) MO=$(BUILD) modules

check:
	@test -d "$(KDIR)" || { \
		echo "ERROR: kernel build dir $(KDIR) not found."; \
		echo "  Debian/Pi : sudo apt install linux-headers-$(KVER)"; \
		echo "  Fedora    : sudo dnf install kernel-devel-$(KVER) kernel-headers"; \
		echo "  or        : make KDIR=/usr/src/kernels/$(KVER)"; \
		exit 1; }

install: default
	$(MAKE) -C $(KDIR) M=$(CURDIR) MO=$(BUILD) modules_install
	depmod -a $(KVER)
	@echo "Installed. On kernels with module signing (Fedora + Secure Boot)"
	@echo "the module must be signed, e.g. via mokutil/sign-file or akmods."

clean:
	@if [ -n "$(BUILD)" ] && [ -d "$(BUILD)" ]; then \
		$(MAKE) -C $(KDIR) M=$(CURDIR) MO=$(BUILD) clean; \
		rm -rf "$(BUILD)"; \
	else \
		$(MAKE) -C $(KDIR) M=$(CURDIR) clean; \
	fi

.PHONY: default check install clean
