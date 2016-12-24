#!/usr/bin/perl
=for comment

  Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2015 Conrad Lara
   See Contributors file for additional contributors

  Copyright (c) 2013 David Rivenburg et al. BroadBand-HamNet

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

=cut

BEGIN {push @INC, '/www/cgi-bin'};
use perlfunc;

http_header();
html_header("$node system information", 1);
print "<body><pre>\n";

print " node: ", nvram_get("node"), "\n";
print "model: ", `/usr/local/bin/get_model`, "\n";

if ( is_hardware_supported() !=1  ){
    print "<font color=\"red\">!!!! UNSUPPORTED DEVICE !!!!</font>\n";
    print "boardid: " , hardware_boardid() , "\n";
    if ( is_hardware_supported == 0 ) {
        print "<font color=\"red\">Device HAS BEEN TESTED AS UNSUPPORTED</font>\n";
    }
    else {
        print "<font color=\"red\">Device has not been tested. Please file a ticket with your experiences.</font>\n";
    }
    print "\n";
}

foreach(`ifconfig -a`)
{
    next unless /^(\S+) .*HWaddr (\S+)/;
    printf "%-6s %s\n", $1, $2;
}

print "\n/proc/cpuinfo\n";
system "cat /proc/cpuinfo";

print "\nnvram\n";
system "uci -c /etc/local/uci show 2>&1";

print "</pre>\n";

page_footer();
print "</body>\n";
print "</html>\n";
