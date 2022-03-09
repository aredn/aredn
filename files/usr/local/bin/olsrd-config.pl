#!/usr/bin/perl -w -I/www/cgi-bin
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

# this script generates the olsrd config file
# static part comes from /etc/config/olsrd.conf
# dynamic part depends on the node configuration

use perlfunc;
use ucifunc;
use tunfunc;

#Check what config file we are building for
if ( !$ARGV[0] ) {
  $UCI_CONF_FILE="olsrd";
} else {
  $UCI_CONF_FILE=$ARGV[0];
}

if ( $UCI_CONF_FILE eq "olsrd6" ) {
  # We only generate entries for IPv4 at moment"
  exit 0;
}

@names = @hosts = @services = @tunnels = ();

# canonical names for this node
# (they show up in reverse order, make the "official" name last)
push @names, $name if ($name = nvram_get("tactical"));
push @names, $name if ($name = nvram_get("node"));

# load the dhcp reservations when in dmz mode
chomp(my $dmz_mode = `/sbin/uci -q get aredn.\@dmz[0].mode`);
if($dmz_mode ne "0")
{
  # add DNS aliases first
  # (see above comment about "tactical" names)
  foreach(`cat /etc/config.mesh/aliases.dmz`) {
    next unless ($ip, $host) = split ' ', $_;
    push @hosts, qq("$ip" "$host");
  }
  #($lanip, $lanmask, $lanbcast, $lannet) = get_ip4_network("eth0.0");
  foreach(`cat /etc/ethers`)
  {
    #stop certain IP's from getting propagated over the mesh
    ($junk, $junk, $noprop) = split ' ', $_;
    next if $noprop eq "#NOPROP";

    next unless ($ip) = /[0-9a-f:]+\s+([\d\.]+)/i;
    next unless $host = ip2hostname($ip);
    push @hosts, qq("$ip" "$host");
  }
}

# Add a name for the dtdlink interface.
if ($name = nvram_get("node"))
{
  my ($dtdip,$dtdmask,$dtdbcast,$dtdnet);
  ($dtdip, $dtdmask, $dtdbcast, $dtdnet) = get_ip4_network(get_interface("dtdlink"));
  push @hosts, qq("$dtdip" "dtdlink.$name.local.mesh");
}

# load the services
foreach(`cat /etc/config/services 2>/dev/null`)
{
  next unless /^\w+:\/\/[\w\-\.]+:\d+(\/[^\|]*)?\|(tcp|udp)\|\w/;
  chomp;
  push @services, $_;
}

# load the tunnels
my @tunnelnames = @section = ();

if (-e "/etc/local/mesh-firewall/02-vtund")
{
  $tunnum=50;
  push(@tunnelnames, &uci_get_names_by_sectiontype("vtun","client"));
  foreach (@tunnelnames)
  {
    $section=&uci_get_named_section("vtun",$_);
    if ($section->{enabled} eq 1)
    {
      push(@tunnels,"tun${tunnum}");
      $tunnum++;
    }
  }

  $tunnum=50 + &get_tunnel_maxclients();
  @tunnelnames=&uci_get_names_by_sectiontype("vtun","server");
  foreach (@tunnelnames)
  {
    $section=&uci_get_named_section("vtun",$_);
    if ($section->{enabled} eq 1)
    {
      push(@tunnels,"tun${tunnum}");
      $tunnum++;
    }
  }
}

# add the nameservice plugin
push @file, qq(\nLoadPlugin "olsrd_nameservice.so.0.4"\n);
push @file, qq({\n);
push @file, qq(    PlParam "sighup-pid-file" "/var/run/dnsmasq/dnsmasq.pid"\n);
push @file, qq(    PlParam "interval" "30"\n);
push @file, qq(    PlParam "timeout" "300"\n);
push @file, qq(    PlParam "name-change-script" "touch /tmp/namechange"\n);
#push @file, qq(    PlParam "lat" "1"\n);
#push @file, qq(    PlParam "lon" "2"\n);
#push @file, qq(    PlParam "laton-file" "/var/run/latlon.js"\n);
#push @file, qq(    PlParam "laton-infile" "/tmp/latlon.txt"\n);
foreach(@names)    { push @file, qq(    PlParam "name" "$_"\n) }
foreach(@hosts)    { push @file, qq(    PlParam $_\n) }
foreach(@services) { push @file, qq(    PlParam "service" "$_"\n) }
push @file, qq(}\n);

# add the ACTIVE tunnel interfaces
if ( @tunnels )
{
  push @file, qq(\nInterface );
  foreach(@tunnels) { push @file, qq("$_" ) }
  push @file, qq(\n{\n);
  push @file, qq(     Ip4Broadcast 255.255.255.255\n);
  push @file, qq(     Mode \"ether\"\n);
  push @file, qq(}\n);
}

# write the file
print @file;
