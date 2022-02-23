#!/usr/bin/perl -w -I/www/cgi-bin

use perlfunc;

$needsrun=nvram_get("nodeupgraded");

if ( ! $needsrun  ){
  print "Node not upgraded, exiting\n";
  exit 0;
}

$config=nvram_get('config');
if ($config ne "mesh")
{
  print "This node was previously configured in non-mesh mode and is no longer implemented.  Returning to \"firstboot\".\n";
  system ("firstboot -y && reboot");
  exit 1;
}

#Prep some variables
$node = nvram_get("node");
$mac2 = mac2ip(get_mac(get_interface("wifi")), 0);
$dtdmac = mac2ip(get_mac(get_interface("lan")), 0);

$cfg = ();
$defaultcfg = ();

open(TMPCONFFILE, ">/tmp/.mesh_setup") or die;

foreach $line (`cat /etc/config.mesh/_setup`)
{
  next if $line =~ /^\s*#/;
  next if $line =~ /^\s*$/;
  $line =~ /^(\w+)\s*=\s*(.*)$/;

  $cfg{$1} = $2;
}

foreach $line (`cat /etc/config.mesh/_setup.default`)
{
  next if $line =~ /^\s*#/;
  next if $line =~ /^\s*$/;
  $line =~ s/<NODE>/$node/;
  $line =~ s/<MAC2>/$mac2/;
  $line =~ s/<DTDMAC>/$dtdmac/;
  $line =~ /^(\w+)\s*=\s*(.*)$/;
  $defaultcfg{$1} = $2;
}

# Set variables in special conditions
if ( ($cfg{dmz_mode} eq '0') || ( $cfg{wan_proto} eq "disabled") ) {
  $cfg{olsrd_gw} = 0;
}

#End special condition overides
foreach $variable( sort keys %defaultcfg )
{
  if ( defined $cfg{$variable} )
  {
    print TMPCONFFILE "$variable = $cfg{$variable}\n";
  }
  else
  {
    print TMPCONFFILE "$variable = $defaultcfg{$variable}\n";
  }
}

# Specific settings for variables that are not in the default config but are added by the system
foreach $variable( 'dmz_dhcp_end', 'dmz_dhcp_limit', 'dmz_dhcp_start', 'dmz_lan_ip', 'dmz_lan_mask', 'wifi_rxant', 'wifi_txant', 'wan_gw', 'wan_ip', 'wan_mask' )
{
  if ( defined $cfg{$variable} )
  {
    print TMPCONFFILE "$variable = $cfg{$variable}\n";
  }
}

close (TMPCONFFILE);

system ("mv /tmp/.mesh_setup /etc/config.mesh/_setup");
print "Updated mode: mesh\n";

#Commit the new combined config
system ("/usr/local/bin/node-setup.pl -a mesh");
nvram_set("nodeupgraded","0");
print "Rebooting node";
system ("reboot");
