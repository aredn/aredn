#!/bin/bash
<<'LICENSE'
  Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2015 Conrad Lara
   See Contributors file for additional contributors

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation version 3 of the License.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.

LICENSE

#This is a build script for use with the OpenWRT Image Builder to create the final images as used by AREDN 

# Initialize variables
FILESDIR="files"

while getopts "v:a:d:f" flag; do
case "$flag" in
    v) REQVERSION=$OPTARG;;
    d) DESTINATION=$OPTARG;;
    f) FILESDIR=$OPTARG;;
esac
done

if [ ! $REQVERSION ]
  then
  echo "A version number must be provided with -v flag"
  exit 1
fi

if [ ! $DESTINATION ]
  then
  echo "A destination folder must be provided with the -d flag"
  exit 1
fi

mkdir -p $DESTINATION;

echo $VERSION > files/etc/mesh-release
fakeroot make image PLATFORM="UBNT" PACKAGES="bridge busybox dnsmasq dropbear iptables kmod-ipt-nathelper kmod-usb-core kmod-usb-uhci kmod-usb2 libgcc mtd ppp ppp-mod-pppoe uhttpd olsrd perl olsrd-mod-arprefresh olsrd-mod-dyn-gw olsrd-mod-httpinfo olsrd-mod-nameservice olsrd-mod-txtinfo olsrd-mod-dot-draw olsrd-mod-watchdog olsrd-mod-secure perlbase-essential perlbase-xsloader perlbase-file perlbase-perlio libpcap tcpdump-mini ntpclient xinetd kmod-ipv6 ip6tables kmod-ip6tables libip6tc ip iptables-mod-ipopt iwinfo libiwinfo socat" FILES="$FILESDIR" BIN_DIR="$DESTINATION/$VERSION"
rename "s/openwrt/bbhn-$VERSION/g" /$DESTINATION/$VERSION/*
