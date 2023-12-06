# Amateur Radio Emergency Data Network AREDN® Firmware 

https://www.arednmesh.org

## About AREDN®

AREDN® wireless networks are deployed by licensed Amateur Radio operators, Technician Class or higher, under FCC Part 97 allocations adjacent to FCC part 15, unlicensed, WIFI, allocations. They are configured as adhoc nodes to form mesh networks. The firmware created below enables the effective use of valuable and dedicated frequencies for communication services to government and private relief organizations in times of disaster or other emergencies.

This firmware enables 802.11 wireless networks to be created and expanded with little to no IT expertise.  A user can deploy a 'node' anywhere to connect to and extend an AREDN® network.  Device hardware options exist to provide sector coverage, build point-to-point links, and connect end point services to the network. High speed link rates are routinely achieved over long distances, e.g. 60Mbps+ on 10MHz channels over 80km links.

For further information on obtaining an Amateur Radio Technician Class license, please refer to https://www.arrl.org/getting-your-technician-license

## Usage Information

### Ethernet Port usage

The standard Ethernet port of an AREDN® device uses the following vlan tags.  An 802.1Q switch is necessary to utilize the vlan tagged networks:

* untagged:  LAN devices - laptop, ipcam, voip phone, etc.
* vlan 1:  WAN - gateway to connect AREDN® network to home network and/or internet (some devices support changing this vlan to an alternate value)
* vlan 2:  DtDLink (device to device) - AREDN® network routing between nodes, typically cross band

The following devices have enhanced Ethernet port usage.  A single cat5 to the device could be plugged into ether the 'main' or 'secondary' port with standard port functionality. Both ports can be used interchangeably and simultaneously with LAN devices on both ports at the same time.

If the device's hardware supports POE (Power Over Ethernet) pass-through from main port to secondary port, an Advanced Setting option will show to turn on/off.  This is useful to power ipCams or other mesh nodes by daisy chaining the network cable from one device to another. Then only one network cable may be needed to reach 2 or 3 devices on the tower. Be sure to check the power capacity in the vendor specifications to not exceed. The first device in the chain will provide the DHCP address to all LAN devices on all nodes (because it powers up first).

* NanoStation M2 XW
* NanoStation M5 XW
* NanoStation M2 XM
* NanoStation M3 XM
* NanoStation M5 XM
* TP-Link CPE210 v1/v1.1
* TP-Link CPE220 v2
* TP-Link CPE220 v3
* TP-Link CPE510 v1/v1.1
* TP-Link WBS210 v1
* TP-Link WBS210 v2
* TP-Link WBS510 v1
* TP-Link WBS510 v2

The Mikrotik hAP AC Lite, Mikrotik hAP ac2, and Mikrotik hAP ac3 are pre-configured with the following VLANs:

* Port 1: WAN Port - Packets in/out of this port are expected to be untagged. The node is (by default) configured to receive a DHCP assigned address from a home network, internet, or other foreign network.
* Port 5: DtDLink Port Mesh Routing -- Connect to another mesh node or 8021.q switch. Packets in/out of this port must be vlan 2 tagged, other packets are ignored.
* Ports 2-4: LAN devices -- Packets in/out of this port are expected to be untagged. The mesh node will (default) DHCP assign an IP address to your computer, ipCam, voip phone, etc. connected to these ports.

The Ubiquiti AirRouter and AirRouter HP are pre-configured with the following VLANs:

* Port "WAN": Packets in/out of this port are expected to be untagged. The node is (by default) configured to receive a DHCP assigned address from a home network, internet, or other foreign network.
* Port 4: DtDLink Port Mesh Routing -- Connect to another mesh node or 8021.q switch. Packets in/out of this port must be vlan 2 tagged, other packets are ignored.
* Ports 1-3: LAN devices -- Packets in/out of this port are expected to be untagged. The mesh node will (default) DHCP assign an IP address to your computer, ipCam, voip phone, etc. connected to these ports.

The GL.iNet GL-AR150 and GL-AR300M16 are pre-configured with the following VLANS:

* Port labeled "WAN": untagged = AREDN® WAN
* Port labeled "LAN": untagged = AREDN® LAN, vlan 2 = DtDLink (device to device)

The GL.iNet GL-AR750 is pre-configured with the following ports, left to right:

* Left Port with internet globe icon:  WAN (untagged)
* Middle Port with "<..>" icon: DtDLink (vlan 2)
* Right Port with "<..>" icon: LAN (untagged)

IMPORTANT: For Gl.iNet devices, when initially installing AREDN® on OpenWRT, you *MUST* uncheck the "Keep Settings" checkbox.

## Submitting Bug Reports

Please submit all issues to https://github.com/aredn/aredn/issues

## Developer Only Information

The AREDN® firmware is based on OpenWrt with additional packages and patches. A Makefile automates the entire process to create firmware images.

### Images built with the instructions below

This is the active 'main' branch with latest AREDN® code. The Amateur Radio community is encouraged to participate in loading the images produced from a "nightly build" and run the AREDN® firmware in a variety of environments. Given new features may not yet be documented, participants should already have a basic knowledge of Linux and networking to understand and provide useful feedback to the Developer submitting the code.

The goal of participation is to obtain confidence that new features and the overall mesh node is stable. The more participation, the earlier an issue is found, the faster an enhancement will be turned into a release.

Please refer to https://github.com/aredn/aredn/issues for a list of outstanding defects.

### Building with Docker
Installing the Docker environment on your windows/linux/mac machine is a pre-requisite. A docker 'container' has been pre-configured with an aredn linux build environment. Alternative instructions are below if you wish to setup your linux install with the compiler pre-requisites necessary to do the build.

To build with docker:
```
docker pull arednmesh/builder
docker run -it --name builder arednmesh/builder
```

To pull an image (or any other file) out of the docker container:
```
docker cp builder:/opt/aredn/aredn/firmware/targets/ath79/generic/<image>.bin <local directory>
```

### Build Prerequisites

Please take a look at the [OpenWrt documentation](https://openwrt.org/docs/guide-developer/build-system/install-buildsystem) for a complete and up to date list of packages for your operating system.

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
git clone https://github.com/aredn/aredn.git
cd aredn
vi config.mk # enter your callsign, etc.
# build default legacy ath79 target ubnt and tplink images
make  
# build and add legacy ath79 target mikrotik images
make SUBTARGET=mikrotik
# build and add ath79 target (latest linux kernel) ubnt, tplink, and gl images
make MAINTARGET=ath79
```

Building the images may take minutes or hours depending on the machine. For more details see [build options](https://openwrt.org/docs/guide-developer/build-system/use-buildsystem).  
Review the build options in config.mk: `-j <nuMBer of cores + 1>`.
`V=s` will give more verbose error messages.

An internet connection is required during the build process. A good internet connection can improve the build time.

You need approximately 10GB of space for the build.

### How to build prior builds of AREDN®

Prior AREDN® images can be rebuilt.  Replace one of the following after
the "cd aredn" command above:

AREDN® release 3.23.12.0

```
git checkout 3.23.12.0
```

AREDN® release 3.23.8.0

```
git checkout 3.23.8.0
```

AREDN® release 3.23.4.0

```
git checkout 3.23.4.0
```

AREDN® release 3.22.12.0

```
git checkout 3.22.12.0
```

AREDN® release 3.22.8.0

```
git checkout 3.22.8.0
```

AREDN® release 3.22.6.0

```
git checkout 3.22.6.0
```

AREDN® release 3.22.1.0

```
git checkout 3.22.1.0
```

AREDN® release 3.21.4.0

```
git checkout 3.21.4.0
```

AREDN® release 3.20.3.1

```
git checkout 3.20.3.1
```

AREDN® release 3.20.3.0

```
git checkout 3.20.3.0
```

AREDN® release 3.19.3.0

```
git checkout 3.19.3.0
```

AREDN® release 3.18.9.0

```
git checkout 3.18.9.0
```

AREDN® release 3.16.2.0

```
git checkout 3.16.2.0
```

AREDN® release 3.16.1.1

```
git checkout 3.16.1.1-make
```

AREDN® build 176

```
git checkout 91ee867
```

Return to most current changes

```
git checkout main
```

### Directory Layout

```
Included in the git Repo:
config.mk    <- build settings
openwrt.mk   <- which openwrt repo and branch/tag/commit to use
feeds.conf/  <- custom package feeds (edit to point to your clone of aredn_packages)
files/       <- file system in AREDN® created images, most customizations go here
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

The patches directory contains quilt patches applied on top of the openwrt git repo defined in config.mk.

If a patch is not yet included upstream, it can be placed in the `patches` directory with
the `quilt` tool. Please configure `quilt` as described in [OpenWrt Quilt](https://openwrt.org/docs/guide-developer/build-system/use-patches-with-buildsystem).  

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

## Submitting new features and patches to AREDN®

The high level steps to submit to this repository https://github.com/aredn/aredn are:

1) create a github account and 'fork' this repo
2) git commit a change into your fork, e.g. https://github.com/ae6xe/aredn
3) create a pull request for https://github.com/aredn/aredn to consider your change
