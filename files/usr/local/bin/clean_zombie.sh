#!/bin/sh
<<'LICENSE'
  Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2018 Joe Ayers AE6XE
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

# Look for hung 'iw' zombie processes prone to hang 
# when available memory is low. 

# wait for rssi_monitor and snrlog to run
sleep 10

for pid in `ps 2>/dev/null | egrep "^\s*\d+\s+root\s+\d+\s+Z\s+\[iw\]"| sed -e "s/^\s*//"| cut -f1 -d\ `
do

  # found an "iw" zombie
  sleep 10 # give time in case process is naturally closing and needs more time
  if [ -d /proc/$pid ] ; then
    date >> /tmp/zombie.log
    ps | egrep "^\s*${pid}" | grep -v grep | tail -1 >> /tmp/zombie.log
    ppid=`cat /proc/$pid/status | grep -i ppid | cut -f2`
    if [ -d /proc/$ppid ] ; then
      ps | egrep "\s*${ppid}" | grep -v grep | tail -1 >> /tmp/zombie.log
      if ( ! `grep crond /proc/$ppid/status 2>&1 > /dev/null` ) then
        if [ $ppid -gt 1 ] ; then 

          # kill the zombie's parent process to free up resources
          kill -9 $ppid 2>&1 >> /tmp/zombie.log
          echo "Killed $ppid" >> /tmp/zombie.log
          if [ `wc -l /tmp/zombie.log | cut -f1 -d\ ` -gt 100 ] ; then

            # keep file size in check
            cp /tmp/zombie.log /tmp/zombie.tmp
            tail -80 /tmp/zombie.tmp > /tmp/zombie.log
            rm -f /tmp/zombie.tmp
          fi
        fi
      fi
    fi
    echo "" >> /tmp/zombie.log
  fi
done
