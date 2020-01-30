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

sub get_server_dns()
{
    my @list;
    my $uciresult;
    my ($rc,$dns)=&uci_get_indexed_option("vtun","network","0","dns");
    return $dns;
}

#################################
# get base network from config
#################################
sub get_server_network_address()
{
    my @list;
    my $uciresult;
    my ($rc,$server_net)=&uci_get_indexed_option("vtun","network","0","start");
    if($rc eq 0 and $server_net ne "")
    {
        # to facilitate overrides (ie. moving the server to a new node)
        # read the file into $mac
        @list = split('\.', $server_net);
    } 
    else
    {
        # or, calc based on eth0 mac address, then store it.
        $mac=get_mac("eth0");
        @MACS=split(/:/, $mac);
        push @list, "172";
        push @list, "31";
        push @list, hex $MACS[5];
        # strip off the high bits
        push @list, ((hex $MACS[4]) << 2) & 255; 
        $server_net=sprintf("%d.%d.%d.%d",$list[0],$list[1],$list[2],$list[3]);

        #($rc,$uciresult)=&uci_add_sectiontype("vtun","network");
        ($rc,$uciresult)=&uci_set_indexed_option("vtun","network","0","start",$server_net);
        $rc=&uci_commit("vtun");
    }
    return @list;
}

sub get_active_tun()
{
    my @active_tun;
    foreach(`ps -w|grep vtun|grep ' tun '`)
    {
        @parts = $_ =~ /.*\:.*-(172-31-.*)\stun\stun.*/g;1;
        $parts[0] =~ s/\-/\./g;
        push(@active_tun,$parts[0]);    
    }
    return @active_tun;
}

# INPUT arg: Array of active tunnel IP's, IP of the tunnel network you are checking
sub is_tunnel_active()
{
    my ($n, @active_tun) = @_;
    my $match=0;
    foreach(@active_tun){
        #print "a=$_, n=$n\n";
        if($n eq $_) {
            $match = 1;
            last;
        }
    }
    return $match; # the return value of the do block   
}

##########################
# Add OLSRD interfaces - NOT NEEDED
##########################
sub add_olsrd_interfaces() {
    my ($sname,$tunstart,$tuncount) = @_;
    my $tuns;

    &uci_add_named_section("olsrd",$sname,"Interface");
    &uci_set_named_option("olsrd",$sname,"Ip4Broadcast","255.255.255.255");
    
    # delete all interfaces first
    &uci_delete_named_option("olsrd",$sname,"interfaces");
 
    for my $i (0..$tuncount-1) {
        $tuns=$tuns . " " if $i;
        $tuns=$tuns . "tun" . $tunstart;
        $tunstart++;
    }
    
    &uci_add_list_named_option("olsrd",$sname,"interfaces","$tuns");
    &uci_commit("olsrd");
}

##########################
# Add network interfaces tun50 thru tun69 - called on install
##########################
sub add_network_interfaces() {

    for (my $tunnum=50; $tunnum<=69; $tunnum++)
    {
        &uci_add_named_section("network_tun","tun${tunnum}","interface");
        &uci_set_named_option("network_tun","tun${tunnum}","ifname","tun${tunnum}");
        &uci_set_named_option("network_tun","tun${tunnum}","proto","none");
    }
    &uci_commit("network_tun");
    &uci_clone("network_tun");
    # required to support node_setup script
    system "cat /etc/config.mesh/network_tun >> /etc/config.mesh/network";
    system "cat /etc/config.mesh/network_tun >> /etc/config/network";
}

#################################
# Check Freespace on / filesystem
#################################
sub check_freespace()
{
    my $fs = `df / | grep -v '^Filesystem' | awk 'NF=6{print \$4}NF==5{print \$3}{}'`;
    chomp $fs;
    return $fs; 
}

sub vpn_setup_required()
{
    my ($navpage) = @_;
    http_header();
    html_header("$node setup", 1);
    print "<body><center><table width=790>";
    print "<tr><td>\n";
    navbar($navpage);
    print "</td></tr>";
    ################# 
    # messages
    #################
    if(@cli_err)
    {
        print "<tr><td align=center><b>ERROR:<br>";
        foreach(@cli_err) { print "$_<br>" }
        print "</b></td></tr>\n";
    }
    print "<tr><td align=center><br><b>";
    print "Tunnel software needs to be installed.<br/>";
    print "<form method='post' action='/cgi-bin/$navpage' enctype='multipart/form-data'>\n";
    print "<input type=submit name=button_install value='Click to install' class='btn_tun_install' />";
    print "</form>";
    print "</b></td></tr>\n";
    print "</table></center></body></html>\n";
    exit;
}


#################################
# Install VTUN Components/config
#################################
sub install_vtun
{   
    # check free disk space - get real values
    $freespace=&check_freespace();
    if($freespace < 600)
    {
        push @cli_err, "Insuffient free disk space!";
        # redirect back to admin page
    } else {

        # Update/Install VTUN
        system "opkg update >/dev/null 2>&1";
        if ($? eq 0) 
        {
            system "opkg install kmod-tun zlib liblzo vtun >/dev/null 2>&1";
            if ($? eq 0) 
            {
                # add network interfaces
                add_network_interfaces();

                # create UCI config file
                system("touch /etc/config/vtun");
                # create options section
                $rc=&uci_add_sectiontype("vtun","options");
                $rc=&uci_commit();

                http_header();
                html_header("TUNNEL INSTALLATION IN PROGRESS", 0);
                print "</head>\n";
                print "<body><center>\n";
                print "<h2>Installing tunnel software...</h2>\n";
                print "<h1>DO NOT REMOVE POWER UNTIL THE INSTALLATION IS FINISHED</h1>\n";
                print "</center><br>\n";
                unless($debug)
                { 
                    print "
                        <center><h2>The node is rebooting</h2>
                        <h3>When the node has fully rebooted you can reconnect with<br>
                        <a href='http://$node.local.mesh:8080/'>http://$node.local.mesh:8080/</a><br>
                        </h3>
                        </center>
                        ";
                     page_footer();
                     print "</body></html>";
                     system "/sbin/reboot" unless $debug;
                     exit;
                }
            } else {
                push @cli_err,"Package installation failed!";
            }
        } else {
            push @cli_err,"Package update failed!";
        }
    }
}

sub generate_ips()
{
    my ($netip) = @_;
    my $serverip = &addrtoint($netip);
    $serverip++;
    $serverip++;
    $serverip=inttoaddr($serverip);
    
    my $clientip = &addrtoint($netip);
    $clientip++;
    $clientip=inttoaddr($clientip);
    
    return ($clientip, $serverip);
}

sub addrtoint { return( unpack( "N", pack( "C4", split( /[.]/,$_[0]))))};
sub inttoaddr { return( join( ".", unpack( "C4", pack( "N", $_[0]))))};

#weird uhttpd/busybox error requires a 1 at the end of this file
1
