# default parameters for Makefile

# What version will show in the AREDN firmware 'Node Status" UI page?
PRIVATE_BUILD_VERSION=3.16.1.1

# build options:  -j# for (# of cores +1) on build machine,  V=s for verbose output
# https://wiki.openwrt.org/doc/howto/build#make_options  (archive)
# https://openwrt.org/docs/guide-developer/usebuildsytem (openwrt-lede merge)
# example "MAKE_ARGS=-j33 V=s IGNORE_ERRORS=m BUILD_LOG=1"
MAKE_ARGS=-j3

# These options are for more complex changes
SHELL:=$(shell which bash)
TARGET=ar71xx-generic
