#!/bin/sh
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

  Additional Terms:

  Additional use restrictions exist on the AREDN(TM) trademark and logo.
    See AREDNLicense.txt for more info.

  Attributions to the AREDN Project must be retained in the source code.
  If importing this code into a new or existing project attribution
  to the AREDN project must be added to the source code.

  You must not misrepresent the origin of the material conained within.

  Modified versions must be modified to attribute to the original source
  and be marked in reasonable ways as differentiate it from the original
  version.

LICENSE

. "$SCRIPTBASE/sh2ju.sh"


# Make sure shellchheck is installed and in path.
juLog -name="usrlocalbinshell_shellcheckexists" which shellcheck
SHELLCHECKEXISTS=$?
echo $SHELLCHECKEXISTS
if [ "$SHELLCHECKEXISTS" = "1" ]; then
  echo "Unable to find shellcheck, tests not run."
  exit 1;
fi

for file in "$AREDNFILESBASE"/usr/local/bin/*
do
  if head -n 1 "$file" | grep "bin/sh" >/dev/null; then
    juLog -name="usrlocalbinshell_$(basename "$file")" shellcheck "$file"
  fi
done
