#!/bin/sh
# Copyright 2014 Conrad Lara

. /lib/functions.sh

include /lib/upgrade/

if (eval platform_check_image "$*")
then
	return 0;
else
	return 1;
fi


