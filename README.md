# Amateur Radio Emergency Data Network AREDN(tm) Firmware

http://www.arednmesh.org

## Build Information for 3.16.2.0

The AREDN firmware is based on OpenWrt with additional packages and patches.
A Makefile automates the entire process to create firmware images.

### Images built

The following images are built:

Device | Image to Use | RAM | Stability
------ | ------------ | --- | ---------
AirGrid XM | bullet-m | 32Mb | stable
AirRouter  | airrouter | 32Mb | stable
AirRouter HP | airrouter | 32Mb | stable
Bullet M2/M5 | bullet-m | 32Mb | stable
Bullet Ti | bullet-m | 32Mb | stable
NanoBridge 2G18 | bullet-m | 32Mb | stable
NanoBridge 5G22/25 | bullet-m | 32Mb | stable
NanoBridge M9 | bullet-m | 32Mb | stable
NanoStation Loco M2/M5/M9 XM | bullet-m | 32Mb | stable
NanoStation  M2/M3/M5 XM | nano-m | 32Mb | stable
NanoStation  M5 XW | nano-m-xw | 64Mb | stable
PicoStation M2 | bullet-m | 32Mb | stable
Rocket M9/M2/M3/M5/M5GPS XM | rocket-m | 64Mb | stable
TPLink CPE210 v1.0 | cpe210-220-v1 | 64Mb | stable
TPLink CPE510 v1.0 | cpe510-220-v1 | 64Mb | stable

### Build Prerequisites

Please take a look at the [OpenWrt documentation](https://openwrt.org/docs/guide-developer/install-buildsystem)
for a complete and up to date list of packages for your operating system. 

On Ubuntu/Debian:
```
apt-get install git subversion build-essential libncurses5-dev \
  zlib1g-dev gawk unzip libxml-perl flex wget gettext quilt \
  python libssl-dev shellcheck lua5.1
```

On openSUSE:
```
zypper install --type pattern devel_basis
zypper install git subversion ncurses-devel zlib-devel gawk unzip \
  perl-libxml-perl flex wget gettext-runtime quilt python \
  libopenssl-devel shellcheck lua51
```

### Building firmware images

To obtain the source and build the firmware locally use:

```bash
git clone https://github.com/aredn/aredn_ar71xx.git
cd aredn_ar71xx
git checkout 3.16.2.0
make
```

Building the images may take minutes or hours depending on the machine.
For more details see [build options](http://wiki.openwrt.org/doc/howto/build#make_options).  
Review the build options in config.mk: `-j <number of cores + 1>`. 
`V=s` will give more verbose error messages.

An internet connection is required during the build process. A good internet
connection can improve the build time.

You need approximately 10GB of space for the build.

### Directory Layout

```
Included in the git Repo:
config.mk    <- build settings
openwrt.mk   <- which openwrt repo and branch/tag/commit to use
feeds.conf/  <- custom package feeds (edit to point to your clone of aredn_packages)
files/       <- file system in AERDN created images, most customizations go here
patches/     <- patches to openwrt go here 
scripts/     <- tests and other scripts called from the build 
configs/     <- definitions of features in the devices' kernel and what packages to include
Makefile     <- the build definition
README.md    <- this file

Created by the build:
openwrt/     <- cloned openwrt repository
firmware/    <- the build will place the images here
results/     <- code checks and other test results in jUnit xml format
```

### Patches with quilt

The patches directory contains quilt patches that are applied on top of the
openwrt git repo defined in config.mk. 

If a patch is not yet included upstream, it can be placed in the `patches` directory with
the `quilt` tool. Please configure `quilt` as described in 
[OpenWrt Quilt](https://openwrt.org/docs/guide-developer/use-patches-with-buildsystem?s[]=quilt).  

#### Add, modify or delete a patch

Switch to the openwrt directory:

```bash
cd openwrt
```
Now you can use the `quilt` commands.

##### Example: add a patch

```bash
quilt push -a                 # apply all patches
quilt new 008-awesome.patch   # tell quilt to create a new patch
quilt edit somedir/somefile1  # edit files
quilt edit somedir/somefile2
quilt refresh                 # creates/updates the patch file
```

## Submitting new features and patches to AREDN

The highlevel steps to submit to this repository https://github.com/aredn/aredn_ar71xx are:

1) create a github account and 'fork' this repo
2) git commit a change into your fork, e.g. http://github.com/ae6xe/aredn_ar71xx
3) create a pull request for http://github.com/aredn/aredn_ar71xx to consider your change

## Submitting Bug Reports

Please submit all issues to http://github.com/aredn/aredn_ar71xx/issues


