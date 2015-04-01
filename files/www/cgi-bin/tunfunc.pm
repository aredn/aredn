#################################
# get base network from config - CHANGE FOR UCI
#################################
sub get_server_network_address()
{
    my @list =();
    my $server_net=`uci get vtun.@network[0].start`;

    if($server_net ne "")
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
        push @list, hex @MACS[5];
        # strip off the high bits
        push @list, ((hex @MACS[4]) << 2) & 255; 

        $server_net=sprintf("%d.%d.%d.%d",@list[0],@list[1],@list[2],@list[3]);
        system "uci add vtun network";
        system "uci set vtun.@network[0].start='${server_net}'";
        system "uci commit vtun";
    }
    return @list;
}

sub get_active_tun()
{
    my @active_tun;
    foreach(`ps -w|grep vtun|grep ' tun '`)
    {
        @parts = $_ =~ /.*\:.*-(172-31-.*)\stun\stun.*/g;1;
        @parts[0] =~ s/\-/\./g;
        push(@active_tun,@parts[0]);    
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

# Get hardware model/type
sub get_model()
{
    $model_full=`/usr/local/bin/get_model`;
    if($model_full=~ m/ubiquiti.*/i) {
        $model="UBNT";
    } else {
        $model="LS";
    }
}

##########################
# Add OLSRD interfaces - called when adding a new client connection
##########################
sub add_olsrd_interface() {
    my ($tunnum) = @_;
    # uci add_list olsrd.interface=vpn${tunnumber} 
    # uci commit vtundsrv

#config Interface 
#        list interface 'vpn50 vpn51 vpn52 vpn53 vpn54 vpn55 vpn56 vpn57 vpn58 vpn59'
#        option Ip4Broadcast 255.255.255.255

}


##########################
# Delete OLSRD interfaces - called when deleting a new client connection
##########################
sub del_olsrd_interface() {
    my ($tunnum) = @_;
    # uci delete_list olsrd.interface.vpn${tunnumber} 
    # uci commit vtundsrv

#config Interface 
#        list interface 'vpn50 vpn51 vpn52 vpn53 vpn54 vpn55 vpn56 vpn57 vpn58 vpn59'
#        option Ip4Broadcast 255.255.255.255
}

##########################
# Add network interfaces tun50 thru tun69 - called on install
##########################
sub add_network_interfaces() {
    for ($tunnum = 50; $tunnum <= 69; $tunnum++)
    {
        system "uci set network.vpn${tunnum}=interface";
        system "uci set network.vpn${tunnum}.ifname='tun${tunnum}";
        system "uci set network.vpn${tunnum}.proto='none'";
    }
    system "uci commit network";
}

##########################
# Delete OLSRD interfaces - called when deleting a new client connection
##########################
sub del_olsrd_interface() {
    my ($tunnum) = @_;
    # uci delete_list olsrd.interface.vpn${tunnumber} 
    # uci commit vtundsrv
    # 
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

##########################
# Config firewall to allow port 5525 on WAN interface
##########################
sub open_5525_on_wan() {
    system "uci add firewall rule";
    system "uci set firewall.@rule[-1].src='wan'";
    system "uci set firewall.@rule[-1].dest_port='5525'";
    system "uci set firewall.@rule[-1].proto='tcp'";
    system "uci set firewall.@rule[-1].target='ACCEPT'";
    system "uci commit firewall";
}



#weird uhttpd/busybox error requires a 1 at the end of this file
1