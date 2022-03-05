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

$VPNVER="1.1";
$config = nvram_get("config");
$node = nvram_get("node");
$node = "NOCALL" if $node eq "";

read_postdata();

#################################
# save clients from form to UCI
#################################
sub save_clients()
{
    my $enabled_count=0;

    for ($i=0; $i < $parms{"client_num"}; $i++) {
        my $net = $parms{"client${i}_netip"};

        $rc=&uci_add_named_section("vtun","client_$i","client");

        # generate the clientip and serverip
        my ($clientip, $serverip) = &generate_ips($net);

        $rc=&uci_set_named_option("vtun","client_$i","netip",$net);
        push(@cli_err,"Problem saving UCI vtun client net IP (#$i): $rc") if $rc;

        $rc=&uci_set_named_option("vtun","client_$i","enabled",$parms{"client${i}_enabled"});
        push(@cli_err,"Problem saving UCI vtun client enabled (#$i): $rc") if $rc;

        $rc=&uci_set_named_option("vtun","client_$i","name",$parms{"client${i}_name"});
        push(@cli_err,"Problem saving UCI vtun client name (#$i): $rc") if $rc;

        $rc=&uci_set_named_option("vtun","client_$i","contact",$parms{"client${i}_contact"});
        push(@cli_err,"Problem saving UCI vtun client contact (#$i): $rc") if $rc;

        $rc=&uci_set_named_option("vtun","client_$i","passwd",$parms{"client${i}_passwd"});
        push(@cli_err,"Problem saving UCI vtun client password (#$i): $rc") if $rc;

        # generate the VTUN NODE name based on the node name and netip
        $net=~ s/\./\-/g;
	#VTUN NODE name must not be more than 23 chars long to avoid username limits!
        my $vtun_node_name=substr($parms{"client${i}_name"},0,23) . "-" . $net;
        $rc=&uci_set_named_option("vtun","client_$i","clientip",$clientip);
        push(@cli_err,"Problem saving UCI vtun client client IP (#$i): $rc") if $rc;

        $rc=&uci_set_named_option("vtun","client_$i","serverip",$serverip);
        push(@cli_err,"Problem saving UCI vtun client server IP (#$i): $rc") if $rc;

        $rc=&uci_set_named_option("vtun","client_$i","node",$vtun_node_name);
        push(@cli_err,"Problem saving UCI vtun client name (#$i): $rc") if $rc;

        $enabled_count++ if $parms{"client${i}_enabled"};
    }

    my $maxclients = &get_tunnel_maxclients();
    push(@cli_err,"Number of clients enabled ($enabled_count) exceeds maxclients ($maxclients); only the first $enabled_count will activate.") if $enabled_count > $maxclients;
}

#################################
# save network info to UCI
#################################
sub save_network()
{
    push(@cli_err,"The third octet of the network MUST be from 0 to 255") unless (($parms{server_net1}>=0) && ($parms{server_net1}<=255) && ($parms{server_net1} ne ''));
    push(@cli_err,"The last octet of the network MUST be from 0 to 255") unless (($parms{server_net2}>=0) && ($parms{server_net2}<=255) && ($parms{server_net2} ne ''));
    push(@cli_err,"The last octet of the network MUST be a multiple of 4 (ie. 0,4,8,12,16,...)") if ($parms{server_net2} % 4);
    push(@cli_err,"Not a valid DNS name") unless (validate_fqdn($parms{dns}));
    if (not @cli_err)
    {
        my $net=sprintf("%d.%d.%d.%d",172,31,$parms{server_net1},$parms{server_net2});
        push @cli_err, "Problem saving the server network values!" if (&uci_set_indexed_option("vtun","network",0,"start",$net));
        push @cli_err, "Problem saving the server DNS name!" if (&uci_set_indexed_option("vtun","network",0,"dns",$dns));
    }
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
&vpn_setup_required("vpn") unless(-e "/usr/sbin/vtund" );

#################
# If RESET, revert the UCI file
#################
if($parms{button_reset})
{
    ($rc,$res)=&uci_revert("vtun");
    ($rc,$res)=&uci_delete_option("vtun","network",0,"start");
    ($rc,$res)=&uci_delete_option("vtun","network",0,"dns");
    $rc=&uci_commit("vtun");
}

#################
# get vtun network address
#################
@netw = ();
@netw = get_server_network_address();
$dns = get_server_dns();

#################
# If RESET or FIRST TIME, load clients/servers from file into parms
#################
if($parms{button_reset} or not $parms{reload})
{
    # revert to previous state on initial load
    ($rc,$res)=&uci_revert("vtun");

    # load clients from UCI
    &get_client_info();

    $parms{server_net1}=$netw[2];
    $parms{server_net2}=$netw[3];

    $parms{dns}=$dns;

    # initialize the "add" entries to clear them
    foreach $var (qw(client_add_enabled client_add_name client_add_passwd))
    {
        $parms{$var} = "";
        $parms{$var} = "0" if($var eq 'client_add_enabled');
    }
}


#################
# load clients from FORM and validate
#################
for($i =0 , @list = (); $i < $parms{client_num}; $i++) { push @list, $i }
push @list, "_add";
$client_num = 0;

foreach $val (@list)
{
    foreach $var (qw(enabled name passwd netip contact))
    {
        $varname = "client${val}_$var";
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
    if($val eq "_add")
    {
        # skip any null values on add or save
        next unless ($enabled or $name or $passwd or $contact) and ($parms{client_add} or $parms{button_save});
    }   # no delete capabilities as net renumbering is not allowed


    if($val eq "_add" and $parms{button_save})
    {
        push @cli_err, "$val this client must be added or cleared out before saving changes";
        next;
    }

    # password MUST be alphanumeric (no special chars)
    push @cli_err, "The password cannot contain non-alphanumeric characters (#$client_num)" if ($passwd =~ m/[^a-zA-Z0-9@]/);
    push @cli_err, "The password must contain at least one alphabetic character (#$client_num)" if ($passwd !~ /\D/);
    push @cli_err, "A client name is required" if($name eq "");
    push @cli_err, "A client password is required" if($passwd eq "");

    next if $val eq "_add" and @cli_err and $cli_err[-1] =~ /^$val /;


    $parms{"client${client_num}_enabled"} = $enabled;
    $parms{"client${client_num}_name"} = uc $name;
    $parms{"client${client_num}_passwd"} = $passwd;
    $parms{"client${client_num}_netip"} = $netip;

    # Commit the data for this client
    $client_num++;

    # Clear out the ADD values
    if($val eq "_add")
    {
        foreach $var (qw(net enabled name passwd netip contact))
            {
                $parms{"client_add_${var}"} = "";
            }
    }
}

$parms{client_num} = $client_num;

#################
# SAVE the server network numbers and dns into the UCI
#################
$netw[2]=$parms{server_net1};
$netw[3]=$parms{server_net2};
$dns=$parms{dns};
$rc=save_network();

#################
# SAVE the clients
#################
$rc=save_clients();

#################
# save configuration (commit)
#################
if($parms{button_save} and not @cli_err)
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
        push(@errors,"Problem restaring vtundsrv") if system "/etc/init.d/vtundsrv restart > /dev/null 2>&1";
        # delay to allow clients to connect and have an accurate "cloud" status
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

print "<form id=vpn method=post action=/cgi-bin/vpn.pl enctype='multipart/form-data'>\n" unless $debug == 2;
print "<form method=post action=test>\n" if $debug == 2;
print "<table width=790>\n";

#################
# Navigation bar
#################
print "<tr><td>\n";
navbar("vpn");
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
if(@cli_err)
{
    print "<tr><td align=center><b>ERROR:<br>";
    foreach(@cli_err) { print "$_<br>" }
    print "</b></td></tr>\n";
}

if($parms{button_save})
{
    if(@cli_err)
    {
	print "<tr><td align=center><b>Configuration NOT saved!</b></td></tr>\n";
    #}
    #elsif(@errors)
    #{
	#print "<tr><td align=center><b>Configuration saved, however:<br>";
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
    &print_vpn_clients();
    print "</td></tr>\n";
    print "<tr><td><hr></td></tr>\n";
}
print "</table>\n";
print "<p style='font-size:8px'>Tunnel v${VPNVER}</p>";
push @hidden, "<input type=hidden name=client_num value=$parms{client_num}>";

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
# List the clients allowed to connect to this server
######################################################
sub print_vpn_clients()
{
    print "<table cellpadding=0 cellspacing=0>";

    print "<br /><tr class=tun_network_row><td colspan=6 align=center valign=top>Tunnel Server Network: ";
    printf("%d.%d.",$netw[0],$netw[1]);
    print "<input type='text' name='server_net1' size='3' maxlen='3' value='$netw[2]' onChange='form.submit()' title='from 0-255' >";
    print ".";
    print "<input type='text' name='server_net2' size='3' maxlen='3' value='$netw[3]' onChange='form.submit()' title='from 0-255 in multiples of 4. (ie. 0,4,8,12,16...252)' >";

    print "<br /><hr>Tunnel Server DNS Name: ";
    print "<input type='text' name='dns' size='30' value='$dns' onChange='form.submit()' ></td></tr>";

    print "</table>";
    #print "<hr />";
    print "<table cellpadding=0 cellspacing=0>";
    print "<tr><th colspan=6 align=center valign=top>&nbsp;</th></tr>\n";
    print "<tr class=tun_client_row>";
    print "<tr><th colspan=6>Allow the following clients to connect to this server:</th></tr>\n";
    print "<tr><th colspan=6><hr></th></tr>\n";
    print "<tr><th>Enabled?</th><th>Client</th><th>Pwd</th><th>Net</th><th>Active&nbsp;</td><th>Action</th></tr>\n";

    for($i = 0, @list = (); $i < $parms{client_num}; ++$i) { push @list, $i };

    push @list, "_add" unless($parms{client_num} >= &get_tunnel_maxclients());

    $cnum=0;
    foreach $val (@list)
    {
        foreach $var (qw(enabled name passwd contact))
        {
            eval sprintf("\$%s = \$parms{client%s_%s}", $var, $val, $var);
        }

        print "<tr class=tun_client_add_row><td height=10></td></tr>\n" if $val eq "_add" and scalar(@list) > 1;
        print "<tr class='tun_client_list2 tun_client_row'>";
        print "<td class='tun_client_center_item' rowspan='2'>";

        # Required to be first, so, if the checkbox is cleared, a value will still POST
        print "<input type='hidden' name='client${val}_enabled' value='0'>" unless($val eq "_add");
        print "<input type='checkbox' name='client${val}_enabled' value='1'";
        print " onChange='form.submit()'" unless $val eq "_add";
        print " checked='checked'" if $enabled;
        print " title='enable this client'></td>";

        print "<td><input type=text size=40 name=client${val}_name value='$name'";
		print " onChange='form.submit()'" unless $val eq "_add";
        # print " disabled" unless $val eq "_add";
		print " title='client name'></td>";

        print "<td><input type=text size=25 name=client${val}_passwd value='$passwd' ";
        print " onChange='form.submit()'" unless $val eq "_add";
        print " title='client password'";
        #print " disabled" unless $val eq "_add";
        print "></td>";

        # handle rollover of netw[3]
        if($netw[3]+($cnum * 4) > 252) {
            $netw[2]++;
            $netw[3] = 0;
            $net=0;
            $cnum=0;
        } else {
            $net=$cnum;
        }

        if($val eq "_add") { $lastnet=$netw[3]+(($net) * 4); }
        else { $lastnet=$netw[3]+($net * 4); }
        $fullnet=sprintf("%d.%d.%d.%d",$netw[0],$netw[1],$netw[2],$lastnet);
        print "<td rowspan='2' class='tun_client_center_item'>&nbsp;$fullnet";
        print "<input type=hidden name=client${val}_netip value='$fullnet'/></td>";
        print "<td rowspan='2' class='tun_client_center_item' align=center>&nbsp;";
        if (&is_tunnel_active($fullnet,@active_tun) && ($val ne "_add")) {
            print "<img class='tun_client_active_img' src='/connected.png' title='Connected' />";
        } else {
            print "<img class='tun_client_inactive_img' src='/disconnected.png' title='Not connected' />";
        }
        print "</td>";
        print "<td rowspan='2' class='tun_client_center_item'><input type=submit name=client_add value=Add title='Add this client'>" if($val eq "_add");
        print "</td>";
        print "<td rowspan='2' class='tun_client_center_item tun_client_mailto'><a href='mailto:?subject=AREDN%20Tunnel%20Connection&body=Your%20connection%20details:%0D%0AName:%20$name%0D%0APassword:%20$passwd%0D%0ANetwork:%20$fullnet%0D%0AServer%20address:%20$dns' target='_blank'><img class='tun_client_mailto_img' src='/email.png' title='Email details' /></a></td>" unless($val eq "_add");

	#contact info for the tunnel
        print "</tr>";
        print "<tr class='tun_client_list1 tun_client_row tun_loading_css_comment'><td colspan='2' align='right'>Contact Info/Comment (Optional): <input type=text maxlength='50' size=40 name=client${val}_contact value='$contact'";
        print " onChange='form.submit()'" unless ($val eq "_add" || $val eq "");
        print " title='client contact info'></td>";

        print "</tr>\n";

        # display any errors
        while(@cli_err and $cli_err[0] =~ /^$val /)
        {
            $err = shift @cli_err;
            $err =~ s/^\S+ //;
            print "<tr class=tun_client_error_row><th colspan=4>$err</th></tr>\n";
        }

        #push @hidden, "<input type='hidden' name='client${val}_enable' value='0'>" unless($val eq "_add");

        print "<tr><td colspan=4 height=4></td></tr>\n";
		$cnum++;
    }
    print "</table>\n";
}

#################################
# load client info from UCI
#################################
sub get_client_info()
{
    my @clients=&uci_get_names_by_sectiontype("vtun","client");
    my $c=0;
    foreach (@clients)
    {
        my $myclient={};
        $myclient=&uci_get_named_section("vtun",$_);
        foreach $var (qw(enabled name passwd netip contact))
        {
            $parms{"client${c}_$var"} = $myclient->{$var};
            $parms{"client${c}_$var"} = "0" if($parms{"client${c}_$var"} eq "");
            $myclient->{$var} = "";
        }
        $c++;
    }

    $parms{client_num} = scalar(@clients);
}

sub DEBUGEXIT()
{
    my ($text) = @_;
    http_header();
    html_header("$node setup", 1);
    print "DEBUG-";
    print $text;
    print "</body>";
    exit;
}
