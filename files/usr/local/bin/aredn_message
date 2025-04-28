#!/bin/sh
true <<'LICENSE'
  Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2020 Darryl Quinn K5DLQ
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

function retrieve_alert() {
  url=$1
  file=$2
  label=$3

  # label is an optional argument
  [ -z "$label" ] && label=$file

  wget -q -O "${file}" -P /tmp "${url}"
  if [ -s "/tmp/${file}" ]; then
    echo "<strong>&#8611; ${label}:</strong>"|cat - "/tmp/${file}" > /tmp/out &&
    echo "<p>" >> /tmp/out &&
    mv /tmp/out "/tmp/${file}"

    # return success
    return 0
  else
    return 1
  fi
}

# does the node have access to downloads.arednmesh.org
ping -q -W10 -c1 downloads.arednmesh.org > /dev/null &&
  online=true;
  [ -f /tmp/aredn_message ] &&
  rm /tmp/aredn_message

nodename=$(echo "$HOSTNAME" | tr 'A-Z' 'a-z')

if [ "$online" = "true" ]
then
  # fetch node specific message file
  retrieve_alert http://downloads.arednmesh.org/messages/${nodename}.txt aredn_message ${nodename}
  if [ $? -ne 0 ] # no node specific file
  then
    # fetch broadcast message file
    retrieve_alert http://downloads.arednmesh.org/messages/all.txt aredn_message "all nodes"
  else
    # need to append to node file
    retrieve_alert http://downloads.arednmesh.org/messages/all.txt aredn_message_all "all nodes"
    if [ -s "/tmp/aredn_message_all" ]; then
      echo "<br />" >> /tmp/aredn_message
      cat /tmp/aredn_message_all >> /tmp/aredn_message
      rm /tmp/aredn_message_all
    fi
  fi
fi

# are local alerts enabled?   uci:  aredn.alerts.localpath != NULL
alertslocalpath=$(uci -q get aredn.@alerts[0].localpath)
if [ -n "$alertslocalpath" ]; then
  cat /dev/null > /tmp/local_message   # initialize local_message file

  # try node specific message file
  retrieve_alert "${alertslocalpath}/${nodename}.txt" "${nodename}-alert" "${nodename}" &&
    FILES="${nodename}"

  # try group messages   uci: aredn.alerts.groups != NULL
  alertgroups=$(uci -q get aredn.@alerts[0].groups)
  if [ -n "$alertgroups" ]; then
    IFS=',' # split multiple groups on comma
    for group in $alertgroups; do
      groupname=$(echo $group | xargs | tr 'A-Z' 'a-z')
      retrieve_alert "${alertslocalpath}/${groupname}.txt" "${groupname}-alert" "${groupname}" &&
        FILES="${FILES} ${groupname}"
    done
    IFS=' '     # reset IFS
  fi

  # try broadcast message file
  retrieve_alert "${alertslocalpath}/all.txt" "all-alert" "all nodes" &&
    FILES="${FILES} all"

  # combine all files
  if [ -n "$FILES" ];then
    for FILE in $FILES; do
      cat /tmp/${FILE}-alert >> /tmp/local_message
      rm /tmp/${FILE}-alert
    done
  fi
fi
