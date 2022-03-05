#!/usr/bin/perl
=for comment

  Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (c) 2015 Darryl Quinn
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

=cut
$debug = 0;
BEGIN {push @INC, '/www/cgi-bin'};
use perlfunc;
use ucifunc;
use tunfunc;

$VPNVER="1.0";
$config = nvram_get("config");
$node = nvram_get("node");
$node = "NOCALL" if $node eq "";

#truncate node name down to 23 chars (max) to avoid vtun issues
#this becomes the vtun "username"
$node = substr($node,0,23);

read_postdata();

#################################
# save server connections from form to UCI
#################################
sub save_connections()
{
    my $enabled_count=0;
    for ($i=0; $i < $parms{"conn_num"}; $i++) {
        
        my $net = $parms{"conn${i}_netip"};
    
        $rc=&uci_add_named_section("vtun","server_$i","server");

        # generate the clientip and serverip
        my ($clientip, $serverip) = &generate_ips($net);

        # generate the VTUN NODE name based on the node name and netip
        $net=~ s/\./\-/g;
        my $vtun_node_name=uc "$node-$net";

        $rc=&uci_set_named_option("vtun","server_$i","clientip",$clientip);
        push(@conn_err,"Problem saving UCI vtun connection client IP (#$i)") if $rc;

        $rc=&uci_set_named_option("vtun","server_$i","serverip",$serverip);
        push(@conn_err,"Problem saving UCI vtun connection server IP (#$i)") if $rc;
        
        $rc=&uci_set_named_option("vtun","server_$i","node",$vtun_node_name);
        push(@conn_err,"Problem saving UCI vtun connection name (#$i)") if $rc;

        $rc=&uci_set_named_option("vtun","server_$i","contact",$contact);
        push(@conn_err,"Problem saving UCI vtun contact info (#$i)") if $rc;

        foreach $var (qw(enabled host passwd netip contact))
        {
            $rc=&uci_set_named_option("vtun","server_$i",$var,$parms{"conn${i}_$var"});
            push(@conn_err,"Problem saving UCI vtun connection (#$i)") if $rc;
        }
        $enabled_count++ if $parms{"conn${i}_enabled"}; 
    }

    my $maxservers = &get_tunnel_maxservers();
    push(@conn_err,"Number of servers enabled ($enabled_count) exceeds maxservers ($maxservers); only the first $maxservers will activate.") if $enabled_count > $maxservers;
}

#################
# page checks
#################
if($parms{button_reboot})
{
    system "/sbin/reboot";
} 

if($parms{button_install})
{
    install_vtun();
} 

reboot_required() if($config eq "" or -e "/tmp/reboot-required");
&vpn_setup_required("vpnc") unless(-e "/usr/sbin/vtund" );

#################
# If RESET, revert the UCI file
#################
if($parms{button_reset})
{
    ($rc,$res)=&uci_revert("vtun");
    $rc=&uci_commit("vtun");
}

#################
# HANDLE connection deletes
#################
for($i = 0; $i < 10; $i++)
{
    $varname="conn${i}_del";
    if($parms{$varname})
    {
        &uci_delete_named_section("vtun","server_${i}");
        for($x = $i+1; $x < 10; $x++)
        {
            $y=$x-1;
            &uci_rename_named_section("vtun","server_$x","server_${y}");
        }
    }
}

#################
# If RESET or FIRST TIME, load servers into parms
#################
if($parms{button_reset} or not $parms{reload}) 
{
 # revert to previous state on initial load
    ($rc,$res)=&uci_revert("vtun");

    # load servers from UCI
    &get_connection_info();
    
    # initialize the "add" entries to clear them
    foreach $var (qw(enabled host passwd netip contact))
    {
        $varname = "conn${val}_$var";
        $parms{$varname} = "";
        $parms{$varname} = "" if($var eq 'enabled');

    }
}

#################
# load connections from FORM and validate
#################
for($i =0 , @list = (); $i < $parms{conn_num}; $i++) { push @list, $i }
push @list, "_add";
$conn_num = 0;

foreach $val (@list)
{
    foreach $var (qw(enabled host passwd netip contact))
    {
        $varname = "conn${val}_$var";
        $parms{$varname} = "0" if($val eq "enabled" and $parms{$varname} eq "");
        $parms{$varname} = "" unless $parms{$varname};
        $parms{$varname} =~ s/^\s+//;
        $parms{$varname} =~ s/\s+$//;
        if($val ne "_add")
        {
            if($parms{$varname} eq "" and ($var eq "enabled"))
            {
                $parms{$varname} = "0"; 
            }
        }
        eval sprintf("\$%s = \$parms{%s}", $var, $varname);
    }


    # Validate ADDed values    
    if($val eq "_add")  { next unless ($enabled or $host or $passwd or $netip or $contact) and ($parms{conn_add} or $parms{button_save}) }
    else                { next if $parms{"conn${val}_del"} }

    # Validate password is vtun compliant
    # TODO

    if($val eq "_add" and $parms{button_save})
    {
        push @conn_err, "$val this connection must be added or cleared out before saving changes";
        next;
    }

    # password MUST be alphanumeric (no special chars)
    push @conn_err, "The password cannot contain non-alphanumeric characters (#$conn_num)" if ($passwd =~ m/[^a-zA-Z0-9@\-]/);
    push @conn_err, "A connection server is required" if($host eq "");
    push @conn_err, "A connection password is required" if($passwd eq "");
    push @conn_err, "A connection network IP is required" if($netip eq "");

    next if $val eq "_add" and @conn_err and $conn_err[-1] =~ /^$val /;

    $parms{"conn${conn_num}_enabled"} = $enabled;
    $parms{"conn${conn_num}_host"} = $host;
    $parms{"conn${conn_num}_passwd"} = $passwd;
    $parms{"conn${conn_num}_netip"} = $netip;
    $parms{"conn${conn_num}_contact"} = $contact;

    # Commit the data for this connection
    $conn_num++;

    # Clear out the ADD values
    if($val eq "_add")
    {
        foreach $var (qw(enabled host passwd netip contact))
            {
                $parms{"conn_add_${var}"} = "";
            }   
    }
}

$parms{conn_num} = $conn_num;

#################
# SAVE the connections
#################
$rc=save_connections();

#################
# SAVE the connections the UCI vtun file
#################
if($parms{button_save} and not @conn_err)
{
   if (&uci_commit("vtun"))
    {
        push(@errors,"Problem committing UCI vtun");
    }
    &uci_clone("vtun");
    unless($debug == 3)
    {
        # Regenerate olsrd files and restart olsrd
        push(@errors,"Problem restarting olsrd") if system "/etc/init.d/olsrd restart > /dev/null 2>&1";
        push(@errors,"Problem restaring vtund") if system "/etc/init.d/vtund restart > /dev/null 2>&1";
        sleep 5;
    }
}

@active_tun=&get_active_tun();

######################################################################################
# generate the page
######################################################################################
http_header() unless $debug == 2;
html_header("$node setup", 1);

print "<body><center>\n";

alert_banner();

print "<form method=post action=/cgi-bin/vpnc.pl enctype='multipart/form-data'>\n" unless $debug == 2;
print "<form method=post action=test>\n" if $debug == 2;
print "<table width=790>\n";

#################
# Navigation bar
#################
print "<tr><td>\n";
navbar("vpnc");
print "</td></tr>\n";

#################
# control buttons
#################
print "<tr><td align=center>";
print "<a href='/help.html#vpn' target='_blank'>Help</a>";
print "&nbsp;&nbsp;&nbsp;\n";
print "<input type=submit name=button_save value='Save Changes' title='Save and use these settings now (takes about 20 seconds)'>&nbsp;\n";
print "<input type=submit name=button_reset value='Reset Values' title='Revert to the last saved settings'>&nbsp;\n";
print "<input type=submit name=button_refresh value='Refresh' title='Refresh this page'>&nbsp;\n";
print "<tr><td>&nbsp;</td></tr>\n";
push @hidden, "<input type=hidden name=reload value=1></td></tr>";

#################
# messages
#################
if(@conn_err)
{
    print "<tr><td align=center><b>ERROR:<br>";
    foreach(@conn_err) { print "$_<br>" }
    print "</b></td></tr>\n";
}

if($parms{button_save})
{
    if(@conn_err)
    {
	print "<tr><td align=center><b>Configuration NOT saved!</b></td></tr>\n";
    }
    elsif(@errors)
    {
	print "<tr><td align=center><b>Configuration saved, however:<br>";
	foreach(@errors) { print "$_<br>" }
	print "</b></td></tr>\n";
    }
    else
    {
	print "<tr><td align=center><b>Configuration saved and is now active.</b></td></tr>\n";
    }

    print "<tr><td>&nbsp;</td></tr>\n";
}

#################
# everything else
#################
if($config eq "mesh")
{
    print "<tr><td align=center valign=top>\n";
    &print_vpn_connections();
    print "</td></tr>\n";
    
    print "<tr><td><hr></td></tr>\n";
}
print "</table>\n";
print "<p style='font-size:8px'>VPN v${VPNVER}</p>";
push @hidden, "<input type=hidden name=conn_num value=$parms{conn_num}>";

#################
# add hidden form fields
#################
foreach(@hidden) { print "$_\n" }

#################
# close the form
#################
print "</form></center>\n";
show_debug_info();

#################
# close the html
#################
page_footer();
print "</body></html>\n";
exit;


##################
# page subsections
##################


######################################################
# List the connections to be made from this client
######################################################
sub print_vpn_connections()
{
    print "<table id=connection_section cellpadding=0 cellspacing=0>";
    print "<tr><th colspan=6>Connect this node to the following servers:</th></tr>";
    print "<tr><th colspan=6><hr></th></tr>\n";
    print "<tr><th>Enabled?</th><th>Server</th><th>Pwd</th><th>Network</th><th>Active&nbsp;</th><th>Action</th></tr>\n";

    for($i = 0, @list = (); $i < $parms{conn_num}; $i++) { push @list, $i };

    push @list, "_add" unless($parms{conn_num} >= &get_tunnel_maxservers());

    $cnum=0;
    foreach $val (@list)
    {
        foreach $var (qw(enabled host passwd netip contact))
        {
            eval sprintf("\$%s = \$parms{conn%s_%s}", $var, $val, $var);
        }

        print "<tr><td height=10></td></tr>\n" if $val eq "_add" and scalar(@list) > 1;
        print "<tr class='tun_client_list2 tun_client_row'>";
        print "<td class='tun_client_center_item' rowspan='2'>";

        # Required to be first, so, if the checkbox is cleared, a value will still POST
        print "<input type='hidden' name='conn${val}_enabled' value='0'>" unless($val eq "_add");
        print "<input type='checkbox' name='conn${val}_enabled' value='1'";
        print " onChange='form.submit()'" unless $val eq "_add";
        print " checked='checked'" if $enabled;
        #print " disabled" unless $val eq "_add";
        print " title='enable this connection'></td>";
 
        print "<td><input type=text size=25 name=conn${val}_host value='$host'";
        print " onChange='form.submit()'" unless $val eq "_add";
        # print " disabled" unless $val eq "_add";
        print " title='connection name'></td>";

        print "<td><input type=text size=20 name=conn${val}_passwd value='$passwd' ";
        print " onChange='form.submit()'" unless $val eq "_add";
        print " title='connection password'";
        #print " disabled" unless $val eq "_add";
        print "></td>";

        print "<td><input type=text size=14 name=conn${val}_netip value='$netip'";
        print " onChange='form.submit()'" unless $val eq "_add";
        # print " disabled" unless $val eq "_add";
        print " title='connection network'></td>";

        print "</td>";
        print "<td class='tun_client_center_item' rowspan='2'>&nbsp;";
        if (&is_tunnel_active($netip,@active_tun) && ($val ne "_add")) {
            print "<img class='tun_client_active_img' src='/connected.png' title='Connected' />";
        } else {
            print "<img class='tun_client_inactive_img' src='/disconnected.png' title='Not connected' />" if ($val ne "_add");
        }
        print "</td>";
        print "<td class='tun_client_center_item' rowspan='2'>&nbsp;";    

        print "<input type=submit name=";
        if($val eq "_add")  { print "conn_add value=Add title='Add this connection'" }
        else                { print "conn${val}_del value=Del title='Delete this connection'" }

        print "></td>";
        #contact info for this tunnel
        print "</tr>\n";
        print "<tr class='tun_client_list1 tun_client_row tun_loading_css_comment'><td colspan='3' align='right'>Contact Info/Comment (Optional): <input type=text maxlength='50' size=40 name=conn${val}_contact value='$contact'";
        print " onChange='form.submit()'" unless ($val eq "_add" || $val eq "");
        print " title='client contact info'></td>";

        print "</tr>\n";

        # display any errors
        while(@conn_err and $conn_err[0] =~ /^$val /)
        {
            $err = shift @conn_err;
            $err =~ s/^\S+ //;
            print "<tr><th colspan=4>$err</th></tr>\n";
        }

        #push @hidden, "<input type='hidden' name='client${val}_enable' value='0'>" unless($val eq "_add");
        
        print "<tr><td colspan=6 height=4></td></tr>\n";
        $cnum++;
    }
    print "</table>\n";
}


#################################
# load server connection info from UCI
#################################
sub get_connection_info()
{
    my @connections=&uci_get_names_by_sectiontype("vtun","server");
    my $c=0;
    foreach (@connections)
    {
        my $myconn={};
        $myconn=&uci_get_named_section("vtun",$_);
        foreach $var (qw(enabled host passwd netip contact))
        {
            $parms{"conn${c}_$var"} = $myconn->{$var};
            $parms{"conn${c}_$var"} = "0" if($parms{"conn${c}_$var"} eq "");
            $myconn->{$var} = "";
        }
        $c++;
    }

    $parms{conn_num} = scalar(@connections);
}


sub DEBUGEXIT()
{
    my ($text) = @_;
    http_header();
    html_header("$node setup", 1);
    print "DEBUG[";
    print $text;
    print "]</body>";
    exit;
}
