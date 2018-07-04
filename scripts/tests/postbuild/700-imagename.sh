#!/bin/sh
<<'LICENSE'
  Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2015-2016 Conrad Lara
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

  Additional Terms:

  Additional use restrictions exist on the AREDN(TM) trademark and logo.
    See AREDNLicense.txt for more info.

  Attributions to the AREDN Project must be retained in the source code.
  If importing this code into a new or existing project attribution
  to the AREDN project must be added to the source code.

  You must not misrepresent the origin of the material contained within.

  Modified versions must be modified to attribute to the original source
  and be marked in reasonable ways as differentiate it from the original
  version.

LICENSE


# Variables that may need adjusting as time goes on

## Values for count of final images
### This value should be updated as we add/remove device image types
NUMBEROFIMAGESCOUNT=60
### Static Files, only when buildroot changes adjust output files types.
### These are files such as  vmlinux, uimage, etc.
STATICFILESCOUNT=141

# END Variables that may need adjusting


. "$SCRIPTBASE/sh2ju.sh"


# Make sure no files named openwrt* in output directory
# Could mean an image rename problem or that the buildroot
# was not clean before making images
if [ "$(find ./openwrt/bin/* -maxdepth 2 -regex '\./openwrt/bin.*[Oo][Pp][Ee][Nn][Ww][Rr][Tt].*' | wc -l)" -eq  "0" ]
then
	juLog -name="no_firmware_images_named_openwrt" true
else
	juLog -name="no_firmware_images_named_openwrt" false
fi




# Check the count of image files  named AREDN-*

## STATICFILESCOUNT + NUMBEROFIMAGESCOUNT * 2 for sysupgrade and factory files
EXPECTEDFILESCOUNT=$(( STATICFILESCOUNT + NUMBEROFIMAGESCOUNT * 2 ))

if [ "$(find ./openwrt/bin/* -maxdepth 2 -regex ".*AREDN-.*" | wc -l)" -eq  "$EXPECTEDFILESCOUNT" ]
then
        juLog -name="AREDN_image_files_exist" true
else
        juLog -name="AREDN_image_files_exist" false
fi

