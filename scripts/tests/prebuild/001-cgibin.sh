#!/bin/sh
<<'LICENSE'
  Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
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

. "$SCRIPTBASE/sh2ju.sh"


# Make sure shellcheck is installed and in path.
juLog -name="cgibin_shellcheckexists" which shellcheck
SHELLCHECKNOTEXISTS=$?

# Make sure luac is installed and in path.
juLog -name="cgibin_luacexists" which luac
LUACNOTEXISTS=$?

# Make sure perl is installed and in path.
juLog -name="cgibin_perlexists" which perl
PERLNOTEXISTS=$?


for file in "$AREDNFILESBASE"/www/cgi-bin/*
do

  FILE_FIRST_LINE=$(head -n 1 "$file") #Lets only read the first line once for the rest of the loops to use

  #### LUA Scripts ####
  if echo "$FILE_FIRST_LINE" | grep "/usr/bin/lua" >/dev/null; then
    if [ "$LUACNOTEXISTS" = "1" ]; then
      juLog -name="cgibin_$(basename "$file")" false # Consider test failed if we don't have luac
    else
      juLog -name="cgibin_$(basename "$file")" luac -p "$file"
    fi
  continue # Next file please
  fi
  #### End LUA Scripts ####


  #### Shell Scripts ####
  if echo "$FILE_FIRST_LINE" | grep "bin/sh" >/dev/null; then
    if [ "$SHELLCHECKNOTEXISTS" = "1" ]; then
      juLog -name="cgibin_$(basename "$file")" false # Consider test failed if we don't have shellcheck
    else
      juLog -name="cgibin_$(basename "$file")" shellcheck -e SC2069,SC2009 "$file"
    fi
  continue # Next file please
  fi
  #### End Shell Scripts ####


  #### Perl Scripts ####
  if echo "$FILE_FIRST_LINE" | grep perl >/dev/null; then
    if [ "$PERLNOTEXISTS" = "1" ]; then
      juLog -name="cgibin_$(basename "$file")" false  # Consider test failed if we don't have Perl
    else
      juLog -name="cgibin_$(basename "$file")" "perl -I $AREDNFILESBASE/www/cgi-bin -cw $file"
    fi
  continue # Next file please
  fi
  #### End Perl Scripts ####

done

