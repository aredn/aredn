#!/bin/sh
# Copyright 2014 Conrad Lara

. /lib/functions.sh

include /lib/upgrade/

if $(platform_check_image "$*" > /dev/null 2>&1)
then
	json=$(/usr/libexec/validate_firmware_image "$*" 2> /dev/null)
	if [ "$(echo "$json" | jsonfilter -e '@.valid')" = "true" ]; then
		return 0;
	fi
	if [ "$(echo "$json" | jsonfilter -e '@.tests.fwtool_signature')" = "false" ]; then
		echo "firmware signature failed"
		return 1;
	fi
	if [ "$(echo "$json" | jsonfilter -e '@.tests.fwtool_device_match')" = "false" ]; then
		if [ -f /tmp/force-upgrade-this-is-dangerous ]; then
			return 0
		else
			echo "firmware device match failed";
			return 1
		fi
	fi
fi
echo "platform check image failed";
return 1
