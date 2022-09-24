# default parameters for Makefile

# What version will show in the AREDN firmware 'Node Status" UI page?
PRIVATE_BUILD_VERSION=NoCall

# build options:  -j# for (# of cores +1) on build machine,  V=s for verbose output
# https://wiki.openwrt.org/doc/howto/build#make_options  (archive)
# https://openwrt.org/docs/guide-developer/usebuildsytem (openwrt-lede merge)
# example "MAKE_ARGS=-j9 V=s IGNORE_ERRORS=m BUILD_LOG=1"
MAKE_ARGS=-j3

# Where will the installed image find add-on Packages to download?
# This URL must contain the packages from this build
# downloading packages within the AREDN UI uses signatures 
PRIVATE_BUILD_PACKAGES=http://downloads.arednmesh.org/snapshots/trunk

# These options are for more complex changes
SHELL:=$(shell which bash)
TARGET=ath79-generic
