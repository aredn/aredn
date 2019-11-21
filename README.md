# Amateur Radio Emergency Data Network AREDN(tm) Firmware

http://www.arednmesh.org

## About AREDN

AREDN wireless networks are deployed by licensed Amateur Radio
operators, Technician Class or higher, under FCC Part 97 allocations
adjacent to FCC part 15, unlicensed, WIFI, allocations. They are
configured as ad-hoc nodes to form mesh networks.  The firmware
created below enables the effective use of valuable and dedicated
frequencies for communication services to government and private
relief organizations in times of disaster or other emergencies.

Amateur Radio frequencies are relatively clean of noise from the commercial
allocations and ensure usability for Amateur Radio Operators.  This firmware
enables 802.11n wireless networks to be created and expanded with minimal 
to no pre-planning or IT expertise.  A user can deploy a 'node' anywhere
to connect in and extend an AREDN network.  Device hardware options exist to
provide sector coverage, build point-to-point links, and connect end
point services to the network. High speed link rates are routinely achieved
over long distances, e.g. 60Mbps+ on 10MHz channels over 80km links. 

For further information on obtaining an Amateur Radio Technician Class
license, please refer to http://www.arrl.org/getting-your-technician-license

## Usage Information

### What to know about the images built with the instructions below

This is the active 'develop' branch with latest AREDN code.
At anytime a new change may be broken or break prior capabilities.

The Amateur Radio community is encouraged to participate in loading the
images produced from a "nightly build" and run the AREDN firmware in a
variety of environments.  Given new features may not yet be documented,
participants should already have a basic knowledge of Linux and Networking to
understand and provide useful feedback to the Developer submitting the
code.

The goal of participation is to obtain confidence that new
features and the overall mesh node is stable.   The more participation,
the earlier an issue is found, the faster an enhancement will be
turned into a release.

Please refer to https://github.com/aredn/aredn_ar71xx/issues
for a list of outstanding defects.

### Images built

Device | Image to Use | RAM | Stability
------ | ------------ | --- | ---------
AirGrid XM | bullet-m | 32Mb | stable
AirGrid XW | loco-m-xw | 32Mb | stable
AirRouter  | airrouter | 32Mb | stable
AirRouter HP | airrouter | 32Mb | stable
Bullet M2/M2Ti/M5/M5Ti | bullet-m | 32Mb | stable
Bullet Ti | bullet-m | 32Mb | stable
Bullet M2 XW | rocket-m-xw | 64Mb | stable
LiteBeam M5 | lbe-m5 | 64Mb | stable
NanoBeam M2-13/M5-16/M5-19 | loco-m-xw | 32Mb | stable
NanoBridge 2G18 | bullet-m | 32Mb | stable
NanoBridge 5G22/25 | bullet-m | 32Mb | stable
NanoBridge M9 | bullet-m | 32Mb | stable
NanoStation Loco M2/M5/M9 XM | bullet-m | 32Mb | stable
NanoStation Loco M2 XW | loco-m-xw | 64Mb | stable
NanoStation Loco M5 XW with test date before ~Nov 2017| loco-m-xw | 64Mb | stable
NanoStation Loco M5 XW with test date on or after ~Nov 2017 | rocket-m-xw | 64Mb | stable
NanoStation  M2/M3/M5 XM | nano-m | 32Mb | stable
NanoStation  M2/M5 XW | nano-m-xw | 64Mb | stable
PicoStation M2 | bullet-m | 32Mb | stable
PowerBeam-M2-400 | loco-m-xw | 64Mb | stable
PowerBeam-M5-300 | loco-m-xw | 64Mb | stable
PowerBeam-M5-400/400ISO/620 | rocket-m-xw | 64Mb | stable
PowerBridge | nano-m  | 64Mb | stable
Rocket M9/M2/M3/M5/M5GPS XM | rocket-m | 64Mb | stable
Rocket M2 XW | loco-m-xw | 64Mb | stable
Rocket M5 XW | rocket-m-xw | 64Mb | stable
Rocket M2 Titanium TI | rocket-m-ti | 64Mb | unknown
Rocket M2 Titanium XW | rocket-m-xw | 64Mb | unknown
Rocket M5 Titanium TI | rocket-m-ti | 64Mb | stable
Rocket M5 Titanium XW | rocket-m-xw | 64Mb | stable
TPLink CPE210 v1.0/v1.1 | cpe210-220-v1 | 64Mb | stable
TPLink CPE210 v2.0 | cpe210-v2 | 64Mb | stable
TPLink CPE210 v3.0 | cpe210-v3 | 64Mb | stable
TPLink CPE220 v2.0 | cpe220-v2 | 64Mb | stable
TPLink CPE220 v3.0 | cpe220-v3 | 64Mb | stable
TPLink CPE510 v1.0/v1.1 | cpe510-520-v1 | 64Mb | stable
TPLink CPE510 v2.0 | cpe510-v2 | 64Mb | stable
TPLink CPE510 v3.0 | cpe510-v3 | 64Mb | stable
TPLink CPE610 v1.0 | cpe610-v1 | 64Mb | stable
TPLink WBS210 v1.0 | wbs210-v1 | 64mb | stable
TPLink WBS510 v2.0 | wbs510-v2 | 64mb | stable
Mikrotik Basebox RB912UAG-5HPnD/2HPnD | mikrotik-nand-large | 64Mb | stable
Mikrotik hAP ac lite 952Ui-5ac2nD | mikrotik-rb-nor-flash-16M-ac | 64Mb | stable
Mikrotik RBLHG-2nD/5nD | mikrotik-rb-nor-flash-16M | 64Mb | stable
Mikrotik RBLHG-5HPnD | mikrotik-rb-nor-flash-16M | 64Mb | stable
Mikrotik RBLHG-2nD-XL/5HPnD-XL | mikrotik-rb-nor-flash-16M | 64Mb | stable
Mikrotik RBLDF-2nD/5nD | mikrotik-rb-nor-flash-16M | 64Mb | stable
Mikrotik QRT5 RB911G-5HPnD-QRT | mikrotik-nand-large | 64Mb | stable
Mikrotik SXTsq 5HPnD/5nD/2nD | mikrotik-rb-nor-flash-16M | 64Mb | stable
GL.iNet GL-AR150 | gl-ar150 | 64Mb | stable
GL.iNet GL-USB150 | gl-usb150 | 64Mb | stable
GL.iNet GL-AR300M16 | gl-ar300m | 64Mb | stable
GL.iNet GL-AR300M w/ 128Mb NAND | None | 64Mb | Not compatible
GL.iNet GL-AR750 | gl-ar750 | 128Mb | stable

Latest Mikrotik installation options are found at: https://www.arednmesh.org/content/installation-instructions-mikrotik-devices

### Ethernet Port usage

The standard Ethernet port of an AREDN device uses the following vlan tags.  An 802.1Q
switch is necessary to utilize the vlan tagged networks:

* untagged:  LAN devices - laptop, ipcam, voip phone, etc.
* vlan 1:  WAN - gateway to connect AREDN network to home network and/or internet
* vlan 2:  DtDLink (device to device) - AREDN network routing between nodes, typically cross band

The following devices have a peculiar port configuration due to a limitation in the Ethernet driver.
The 'Main" port is used for LAN devices only.  The "Secondary" port is WAN and DtDLink usage
only. Depending on deployed usage, 2 cat5 cables may be needed.

* TP-Link CPE210 v1.0 and v1.1
* TP-Link CPE510 v1.0 and v1.1

The following devices have enhanced Ethernet port usage.  A single cat5 to the device
could be plugged into ether the 'main' or 'secondary' port with standard port functionality.
Both ports can be used interchangeably and simultaneously with LAN devices on both ports
at the same time. POE PassThough can be turned on in Advanced Settings to power ipCams or
other mesh nodes.

* NanoStation M5 XW
* NanoStation M2 XW
* NanoStation M2 XM
* NanoStation M3 XM
* NanoStation M5 XM

The Mikrotik hAP AC Lite, Ubiquiti AirRouter, and AirRouter HP are pre-configured with the following VLANs:

* Port 1: WAN Port - Packets in/out of this port are expected to be untagged. The node is (by default) configured to receive a DHCP assigned address from a home network, internet, or other foreign network.
* Port 5: DtDLink Port Mesh Routing -- Connect to another mesh node or 8021.q switch. Packets in/out of this port must be vlan 2 tagged, other packets are ignored.
* Ports 2-4: LAN devices -- Packets in/out of this port are expected to be untagged. The mesh node will (default) DHCP assign an IP address to your computer, ipCam, voip phone, etc. connected to these ports.


The GL.iNet GL-AR150 and GL-AR300M16 are pre-configured with the following VLANS:

* Port labeled "WAN": untagged = AREDN WAN
* Port labeled "LAN": untagged = AREDN LAN, vlan 2 = DtDLink (device to device)

The GL.iNet GL-AR750 is pre-configured with the following ports, left to right:

* Left Port with internet globe icon:  WAN (untagged)
* Middle Port with "<..>" icon: LAN (untagged)
* Right Port with "<..>" icon: DtDLink (vlan 2)

IMPORTANT: For Gl.iNet devices, when initially installing AREDN on OpenWRT, you *MUST* uncheck the "Keep Settings" checkbox.
 
## Submitting Bug Reports

Please submit all issues to http://github.com/aredn/aredn_ar71xx/issues

## Developer Only Information

The AREDN firmware is based on OpenWrt with additional packages and patches.
A Makefile automates the entire process to create firmware images.

### Building with Docker
Installing the Docker environment on your windows/linux/mac machine is a pre-requisite. A docker 'container' has been pre-configured with an aredn linux build environment. Alternative instructions are below if you wish to setup your linux install with the compiler pre-requisites necessary to do the build.

To build with docker:
```
docker pull arednmesh/builder
docker run -it --name builder arednmesh/builder
```

To pull an image (or any other file) out of the docker container:
```
docker cp builder:/opt/aredn/aredn_ar71xx/firmware/targets/ar71xx/generic/<image>.bin <local directory>
```

### Build Prerequisites

Please take a look at the [OpenWrt documentation](https://openwrt.org/docs/guide-developer/build-system/install-buildsystem)
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

On Arch:
```
pacman -S base-devel subversion zlib unzip perl-xml-libxml wget \
  quilt openssl shellcheck lua51 git
```

### Building firmware images

To obtain the source and build the firmware locally use:

```
bash
git clone https://github.com/aredn/aredn_ar71xx.git
cd aredn_ar71xx
vi config.mk # enter your callsign, etc.
# build default ubnt and tplink images
make  
# build and add mikrotik images to firmware dir
make SUBTARGET=mikrotik
```

Building the images may take minutes or hours depending on the machine.
For more details see [build options](https://openwrt.org/docs/guide-developer/build-system/use-buildsystem).  
Review the build options in config.mk: `-j <number of cores + 1>`. 
`V=s` will give more verbose error messages.

An internet connection is required during the build process. A good internet
connection can improve the build time.

You need approximately 10GB of space for the build.

### How to build prior builds of AREDN

Prior AREDN images can be rebuilt.  Replace one of the following after
the "cd aredn_ar71xx" command above:

AREDN release 3.19.3.0

```
git checkout 3.19.3.0
```

AREDN release 3.18.9.0

```
git checkout 3.18.9.0
```

AREDN release 3.16.2.0

```
git checkout 3.16.2.0
```

AREDN release 3.16.1.1

```
git checkout 3.16.1.1-make
```

AREDN build 176

```
git checkout 91ee867
```

Return to most current changes

```
git checkout develop
```

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

The patches directory contains quilt patches applied on top of the
openwrt git repo defined in config.mk. 

If a patch is not yet included upstream, it can be placed in the `patches` directory with
the `quilt` tool. Please configure `quilt` as described in 
[OpenWrt Quilt](https://openwrt.org/docs/guide-developer/build-system/use-patches-with-buildsystem).  

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

The high level steps to submit to this repository https://github.com/aredn/aredn_ar71xx are:

1) create a github account and 'fork' this repo
2) git commit a change into your fork, e.g. http://github.com/ae6xe/aredn_ar71xx
3) create a pull request for http://github.com/aredn/aredn_ar71xx to consider your change



