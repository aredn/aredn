#!/bin/sh
<<'LICENSE'
  Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
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

  Additional use restrictions exist on the AREDN® trademark and logo.
    See AREDNLicense.txt for more info.

  Attributions to the AREDN® Project must be retained in the source code.
  If importing this code into a new or existing project attribution
  to the AREDN® project must be added to the source code.

  You must not misrepresent the origin of the material contained within.

  Modified versions must be modified to attribute to the original source
  and be marked in reasonable ways as differentiate it from the original
  version.

LICENSE

if [ "${OSTYPE#*darwin}" != "$OSTYPE" ]
then
    SCRIPTBASE=$(dirname "$0")
    export SCRIPTBASE
else
    SCRIPTBASE=$(dirname "$(readlink -f "$0")")
    export SCRIPTBASE
fi

if [ "$1" != "" ]
then
  AREDNFILESBASE=$1
else
  AREDNFILESBASE="$PWD/files"
fi

if [ ! -d "$AREDNFILESBASE" ]
then
  echo "ERROR: $AREDNFILESBASE doesn't exist"
  exit 1;
fi

export AREDNFILESBASE


for file in $SCRIPTBASE/tests/postbuild/*
do
  if [ -x "$file" ]; then
    $file
  fi
done

# Make sure we return clean as to not stop the BuildBot
exit 0
