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

$debug = 0;

BEGIN {push @INC, '/www/cgi-bin'};
use perlfunc;

# collect some variables
$node = nvram_get("node");
$node = "NOCALL" if $node eq "";

read_postdata();

system "mkdir -p /tmp/web";
system "/usr/local/bin/wscan -w > /tmp/web/wscan.next" unless $parms{stop};
system "touch /tmp/web/autoscan" if $parms{auto};
system "rm -f /tmp/web/autoscan" if $parms{stop};
system "mv /tmp/web/wscan.next /tmp/web/wscan" unless $parms{stop};

# generate the page
http_header();
html_header("$node WiFi scan", 0);
print "<meta http-equiv='refresh' content='5;url=/cgi-bin/scan'>\n" if -f "/tmp/web/autoscan";
print "<script src=\"/js/sorttable-min.js\"></script>";
print "<style>                                                   
table.sortable thead {                                          
    background-color:#eee;                                     
    color:#666666;                            
    font-weight: bold;
    cursor: default;                                               
}                                                                      
</style>";
print "</head>\n";
print "<body><form method=post action=/cgi-bin/scan enctype='multipart/form-data'>\n";
print "<center>\n";
alert_banner();
print "<h1>$node WiFi scan</h1><hr>\n";

if(-f "/tmp/web/autoscan")
{
    print "<input type=submit name=stop value=Stop title='Abort continuous scan'>\n";
}
else
{
    print "<input type=submit name=refresh value=Refresh title='Refresh this page'>\n";
    print "&nbsp;&nbsp;&nbsp;\n";
    print "<input type=submit name=auto value=Auto title='Begin continuous scan'>\n";
}

print "&nbsp;&nbsp;&nbsp;\n";
print "<button type=button onClick='window.location=\"status\"' title='Return to status page'>Quit</button><br><br>\n";
system "cat /tmp/web/wscan";
print "<br>";
print "</center>\n";
print "</form>\n";

show_debug_info();
show_parse_errors();

page_footer();
print "</body>\n";
print "</html>\n";
