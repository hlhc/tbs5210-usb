# Kbuild for the standalone TBS5210 driver set.
#
# Builds against the running kernel's own dvb-core/dvb-usb; does NOT
# ship a v4l media tree.  The private header vendor/dvb-usb.h is
# vendored and must match the target kernel's dvb-usb core ABI.

ccflags-y += -I$(src)/vendor/
ccflags-y += -I$(src)/frontends/
ccflags-y += -I$(src)/tuners/

# USB bridge device driver (links against the kernel's dvb-usb module)
dvb-usb-tbs5210-y := dvb-usb/tbs5210.o
obj-m += dvb-usb-tbs5210.o

# DTMB demodulator (i2c driver, loaded on demand by tbs5210)
gx1503-y := frontends/gx1503.o
obj-m += gx1503.o

# Rafael Micro R850 silicon tuner (exports r850_attach)
r850-y := tuners/r850.o
obj-m += r850.o
