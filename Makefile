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

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build

default: check
	$(MAKE) -C $(KDIR) M=$(PWD) modules

check:
	@test -d "$(KDIR)" || { \
		echo "ERROR: kernel build dir $(KDIR) not found."; \
		echo "  Debian/Pi : sudo apt install linux-headers-$(KVER)"; \
		echo "  Fedora    : sudo dnf install kernel-devel-$(KVER) kernel-headers"; \
		echo "  or        : make KDIR=/usr/src/kernels/$(KVER)"; \
		exit 1; }

install: default
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install
	depmod -a $(KVER)
	@echo "Installed. On kernels with module signing (Fedora + Secure Boot)"
	@echo "the module must be signed, e.g. via mokutil/sign-file or akmods."

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

.PHONY: default check install clean
