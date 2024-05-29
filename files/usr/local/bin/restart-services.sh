#! /bin/sh
true <<'LICENSE'
  Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2023 Tim Wilkinson
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

ROOT="/tmp/reboot-required"
SERVICES="log system firewall network wireless dnsmasq tunnels manager olsrd localservices"

ignore=0
force=0
if [ "$1" = "--force" ]; then
  shift
  ignore=1
  force=1
fi
if [ "$1" = "--ignore-reboot" ]; then
  shift
  ignore=1
fi

# Anything to do?
if [ ! -d $ROOT -a $force = 0 ]; then
  exit 0
fi

# If we have to reboot, do nothing (unless ignored)
if [ -f $ROOT/reboot -a $ignore = 0 ]; then
  exit 1
fi

# Override services to restart
if [ "$*" != "" ]; then
  SERVICES="$*"
fi

for srv in $SERVICES
do
  if [ -f $ROOT/$srv -o $force = 1 ]; then
    echo "Restarting $srv"
    if [ $srv = "tunnels" ]; then
      /etc/init.d/vtund restart > /dev/null 2>&1
      /etc/init.d/vtundsrv restart > /dev/null 2>&1
    elif [ $srv = "wireless" ]; then
      /sbin/wifi reload > /dev/null 2>&1
    elif [ $srv = "localservices" ]; then
      /etc/local/services > /dev/null 2>&1
    elif [ -x /etc/init.d/$srv ]; then
      /etc/init.d/$srv restart > /dev/null 2>&1
    fi
    rm -f $ROOT/$srv
  fi
done

rmdir --ignore-fail-on-non-empty $ROOT 2> /dev/null
if [ -d $ROOT ]; then
  exit 1
fi

exit 0
