#! /bin/sh
true <<'LICENSE'
  Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2022 Tim Wilkinson 2022
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

#
# ServiceName[:ServiceDaemon] pairs.
# If ServiceDaemon is omitted, we wont first kill the daemon
#
SERVICES="dnsmasq:dnsmasq dropbear:dropbear urngd:urngd rpcd:rpcd telnet:telnetd manager:manager.lua log:logd"

if [ "$1" = "restore" ]; then
    #
    # Restart everything
    #
    for S in ${SERVICES}
    do
        srv=$(echo ${S} | cut -d: -f1)
        if [ -x /etc/init.d/${srv} ]; then
            /etc/init.d/${srv} start
        fi
    done
else
    #
    # We unceremoniously kill services, and then stop them to prevent
    # procd restarting them again
    #
    for S in ${SERVICES}
    do
        srv=$(echo ${S} | cut -d: -f1)
        daemon=$(echo ${S} | cut -d: -f2 -s)
        if [ "${daemon}" != "" ]; then
            killall -KILL ${daemon}
        fi
        if [ -x /etc/init.d/${srv} ]; then
            /etc/init.d/${srv} stop
        fi
    done

    #
    # Drop page cache to take pressure of tmps
    #
    echo 3 > /proc/sys/vm/drop_caches
fi
