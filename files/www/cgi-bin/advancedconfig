#!/usr/bin/perl
=for comment

  Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2020 - Darryl Quinn
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
use ucifunc;
use tunfunc;

$debug = 0;
$| = 1;

# ---------------------------------------- ADVANCED CONFIG ALLOWED UCI VALUES ------------------
@setting = ();
push @setting, {
  key => "aredn.\@map[0].maptiles",
  type => "string",
  desc => "Specifies the URL of the location to access map tiles",
  default => "http://stamen-tiles-{s}.a.ssl.fastly.net/terrain/{z}/{x}/{y}.jpg"
};
push @setting, {
  key => "aredn.\@map[0].leafletcss",
  type => "string",
  desc => "Specifies the URL of the leaflet.css file",
  default => "http://cdn.leafletjs.com/leaflet/v0.7.7/leaflet.css"
};
push @setting, {
  key => "aredn.\@map[0].leafletjs",
  type => "string",
  desc => "Specifies the URL of the leaflet.js file",
  default => "http://cdn.leafletjs.com/leaflet/v0.7.7/leaflet.js"
};
push @setting, {
  key => "aredn.\@downloads[0].firmwarepath",
  type => "string",
  desc => "Specifies the URL of the location from which firmware files will be downloaded.",
  default => "http://downloads.arednmesh.org/firmware"
};
push @setting, {
  key => "aredn.\@downloads[0].pkgs_core",
  type => "string",
  desc => "Specifies the URL for the 'core' packages: kernel modules and the like",
  default => defaultPackageRepos('aredn_core'),
  postcallback => "writePackageRepo('core')"
};
push @setting, {
  key => "aredn.\@downloads[0].pkgs_base",
  type => "string",
  desc => "Specifies the URL for the 'base' packages: libraries, shells, etc.",
  default => defaultPackageRepos('base'),
  postcallback => "writePackageRepo('base')"
};
push @setting, {
  key => "aredn.\@downloads[0].pkgs_arednpackages",
  type => "string",
  desc => "Specifies the URL for the 'arednpackages' packages: vtun, etc.",
  default => defaultPackageRepos('arednpackages'),
  postcallback => "writePackageRepo('arednpackages')"
};
push @setting, {
  key => "aredn.\@downloads[0].pkgs_luci",
  type => "string",
  desc => "Specifies the URL for the 'luci' packages: luci and things needed for luci.",
  default => defaultPackageRepos('luci'),
  postcallback => "writePackageRepo('luci')"
};
push @setting, {
  key => "aredn.\@downloads[0].pkgs_packages",
  type => "string",
  desc => "Specifies the URL for the 'packages' packages: everything not included in the other dirs.",
  default => defaultPackageRepos('packages'),
  postcallback => "writePackageRepo('packages')"
};
push @setting, {
  key => "aredn.\@downloads[0].pkgs_routing",
  type => "string",
  desc => "Specifies the URL for the 'routing' packages: olsr, etc.",
  default => defaultPackageRepos('routing'),
  postcallback => "writePackageRepo('routing')"
};
push @setting, {
  key => "aredn.\@downloads[0].pkgs_telephony",
  type => "string",
  desc => "Specifies the URL for the 'telephony' packages.",
  default => defaultPackageRepos('telephony'),
  postcallback => "writePackageRepo('telephony')"
};
push @setting, {
  key => "aredn.\@downloads[0].pkgs_freifunk",
  type => "string",
  desc => "Specifies the URL for the 'freifunk' packages.",
  default => defaultPackageRepos('freifunk'),
  postcallback => "writePackageRepo('freifunk')"
};

push @setting, {
  key => "aredn.\@poe[0].passthrough",
  type => "boolean",
  desc => "Specifies whether a PoE passthrough port should be on or off.  (Not all devices have PoE passthrough ports.",
  default => "0",
  condition => "hasPOE()",
  postcallback => "setPOEOutput()"
};
push @setting, {
  key => "aredn.\@usb[0].passthrough",
  type => "boolean",
  desc => "Specifies whether the USB port should be on or off.  (Not all devices have USB powered ports.",
  default => "1",
  postcallback => "setUSBOutput()",
  condition => "hasUSB()"
};
my $tunnelLimitsUpperBound = 100; # maxclients/maxservers cannot exceed this value
push @setting, {
  key => "aredn.\@tunnel[0].maxclients", 
  type => "string", 
  desc => "Specifies the maximum number of tunnel clients this node can serve; must be an integer in the range [0,$tunnelLimitsUpperBound].  (Only applies if tunnel software is installed)", 
  default => "10", 
  condition => "hasTunnelSoftware()",
  precallback => "restrictTunnelLimitToValidRange",
  postcallback => "adjustTunnelInterfaceCount()"
};
push @setting, {
  key => "aredn.\@tunnel[0].maxservers", 
  type => "string", 
  desc => "Specifies the maximum number of tunnel servers to which this node can connect; must be an integer in the range [0,$tunnelLimitsUpperBound].  (Only applies if tunnel software is installed)", 
  default => "10", 
  condition => "hasTunnelSoftware()",
  precallback => "restrictTunnelLimitToValidRange",
  postcallback => "adjustTunnelInterfaceCount()"
};
push @setting, {
  key => "aredn.\@meshstatus[0].lowmem",
  type => "string",
  desc => "Specifies the low memory threshold (in KB) when we will truncate the mesh status page",
  default => "10000"
};
push @setting, {
  key => "aredn.\@meshstatus[0].lowroutes",
  type => "string",
  desc => "When low memory is detected, limit the number of routes shown on the mesh status page",
  default => "1000"
};
push @setting, {
  key => "aredn.olsr.restart",
  type => "none",
  desc => "Will restart OLSR when saving setting -- wait up to 2 or 3 minutes to receive response.",
  default => "0",
  postcallback => "olsr_restart()"
};
push @setting, {
  key => "aredn.aam.refresh",
  type => "none",
  desc => "Attempt to pull any AREDN Alert messages.",
  default => "0",
  postcallback => "aam_refresh()"
};
push @setting, {
  key => "aredn.\@alerts[0].localpath",
  type => "string",
  desc => "Specifies the URL of the location from which local AREDN Alerts can be downloaded.",
  default => ""
};
push @setting, {
  key => "aredn.aam.purge",
  type => "none",
  desc => "Immediately purge/delete all AREDN (and local) Alerts from this node.",
  default => "",
  postcallback => "alert_purge()"
};
# ----------------------------------------

# ----- CONDITIONS ----------
sub hasPOE()
{
  $pin=`cat /etc/board.json|jsonfilter -e '@.gpioswitch.poe_passthrough.pin'`;
  chomp($pin);
  return $pin ? return 1 : return 0;
}

sub hasUSB()
{
  $pin=`cat /etc/board.json|jsonfilter -e '@.gpioswitch.usb_power_switch.pin'`;
  chomp($pin);
  return $pin ? return 1 : return 0;
}

sub hasTunnelSoftware()
{
  return (-e "/usr/sbin/vtund") ? 1 : 0;
}
# ----- CONDITIONS ----------


# ----- CALLBACKS ----------
sub setPOEOutput()
{
  $newval="0" if(!$newval);
  system("/usr/local/bin/poe_passthrough",$newval);
}

sub setUSBOutput()
{
  $newval="0" if(!$newval);
  system("/usr/local/bin/usb_passthrough",$newval);
}

sub olsr_restart()
{
  $rc=`/etc/init.d/olsrd restart`;
  return $rc;
}

sub aam_refresh()
{
  $rc=`/usr/local/bin/aredn_message.sh`;
  return $rc;
}

sub alert_purge()
{
  unlink("/tmp/aredn_message");
  unlink("/tmp/local_message");
  return 0;
}

sub writePackageRepo {
  my $repo = @_[0];
  my $uciurl = `uci get aredn.\@downloads[0].pkgs_$repo`;
  chomp($uciurl);
  my $file = '/etc/opkg/distfeeds.conf';
  my $disturl = `grep aredn_$repo /etc/opkg/distfeeds.conf | cut -d' ' -f3`;
  chomp($disturl);
  system("sed -i 's|$disturl|$uciurl|g' $file");
}

sub restrictTunnelLimitToValidRange() {
    $newval =~ s/^\s+|\s+$//g;
    if ($newval !~ /^\s*-?\d+\s*$/) {
        push @msg, "$key must be an integer in the range [0,$tunnelLimitsUpperBound]";
        $newval = 0
    } elsif ($newval < 0) {
        push @msg, "Lower limit of $key is 0";
        $newval = 0
    } elsif ($newval > $tunnelLimitsUpperBound) {
        push @msg, "Upper limit of $key is $tunnelLimitsUpperBound";
        $newval = $tunnelLimitsUpperBound
    }
}

sub addTunnelInterface() {
    my ($configfile, $tunnum) = @_;
    &uci_add_named_section($configfile,"tun${tunnum}","interface");
    &uci_set_named_option($configfile,"tun${tunnum}","ifname","tun${tunnum}");
    &uci_set_named_option($configfile,"tun${tunnum}","proto","none");
}

sub adjustTunnelInterfaceCount() {
    my $tunnelIfCount = &get_tunnel_interface_count();
    my $neededIfCount = &get_tunnel_maxclients() + &get_tunnel_maxservers();

    if ($tunnelIfCount != $neededIfCount) {
        for (my $i = $tunnelIfCount; $i < $neededIfCount; $i++) {
            my $tunnum = $i + 50;
            &addTunnelInterface("network_tun",$tunnum);
            &addTunnelInterface("network",$tunnum);
        }
        for (my $i = $tunnelIfCount - 1; $i >= $neededIfCount; $i--) {
            my $tunnum = $i + 50;
            &uci_delete_named_section("network_tun","tun${tunnum}");
            &uci_delete_named_section("network","tun${tunnum}");
        }
        &uci_commit("network_tun");
        &uci_commit("network");
        &uci_clone("network_tun");
        # can't clone network because it contains macros; re-edit it instead:
        system "sed -i"
                . " -e '\$r /etc/config.mesh/network_tun'"
                . " -e '/interface.*tun/,\$d'"
                . " /etc/config.mesh/network";
    }
}
# ----- CALLBACKS ----------

read_postdata({acceptfile => false});

if($parms{button_firstboot})
{
    system "firstboot -y";
    reboot_page("/cgi-bin/status");
}

reboot_page("/cgi-bin/status") if $parms{button_reboot};
$node = nvram_get("node");

# make developer mode stick
system "touch /tmp/developer_mode" if $parms{dev};
$parms{dev} = 1 if -e "/tmp/developer_mode";

#
# process POSTED data
#
$scount = scalar @setting;
for($i=0;$i<$scount;$i++)
{
  if($parms{eval "button_save_" . $i})
  {
    $newvalfield=eval "newval_" . $i;
    $newval=$parms{$newvalfield};
    $newval=~ s/^\s+|\s+$//;
    if ($setting[$i]->{'type'} eq "boolean")
    {
      if ($newval)
      {
          $newval="1";
      }
      else
      {
          $newval="0";
      }
    }
    $key=$setting[$i]->{'key'};
    @x=split(/\./, $setting[$i]->{'key'});
    $cfgfile=$x[0];

    # run precallbacks
    eval $setting[$i]->{'precallback'} if($setting[$i]->{'precallback'});

    # set "live" settings
    system("uci set '$key=$newval'");
    system("uci commit '$cfgfile'");

    # set AREDN config settings (used after a "Save Settings" on the Setup page)
    system("uci -S -c /etc/config.mesh set '$key=$newval'");
    system("uci -S -c /etc/config.mesh commit '$cfgfile'");

    push @msg, "Changed $key";

    # run postcallbacks
    eval $setting[$i]->{'postcallback'} if($setting[$i]->{'postcallback'});

    last;
  }
}

#
# generate the page
#

http_header();
html_header("$node Advanced Configuration", 0);
print <<EOF;
<style>
 /* The switch - the box around the slider */
.switch {
  position: relative;
  display: inline-block;
  width: 60px;
  height: 34px;
}

/* Hide default HTML checkbox */
.switch input {
  opacity: 0;
  width: 0;
  height: 0;
}

/* The slider */
.slider {
  position: absolute;
  cursor: pointer;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: #ccc;
  -webkit-transition: .4s;
  transition: .4s;
}

.slider:before {
  position: absolute;
  content: "";
  height: 26px;
  width: 26px;
  left: 4px;
  bottom: 4px;
  background-color: white;
  -webkit-transition: .4s;
  transition: .4s;
}

input:checked + .slider {
  background-color: #2196F3;
}

input:focus + .slider {
  box-shadow: 0 0 1px #2196F3;
}

input:checked + .slider:before {
  -webkit-transform: translateX(26px);
  -ms-transform: translateX(26px);
  transform: translateX(26px);
}

/* Rounded sliders */
.slider.round {
  border-radius: 34px;
}

.slider.round:before {
  border-radius: 50%;
}
</style>

<script>
function toggleDefault(fname, defval) {
  if(document.getElementById(fname).checked) {
    cval = '1'
  } else {
    cval = '0'
  }
  if(cval != defval) {
    document.getElementById(fname).click();
  }
  return true;
}
</script>
</head>
EOF


print "<body><center>\n";
alert_banner();
print "<div style=\"padding:5px;background-color:#FF0000;color:#FFFFFF;width:650px;\"><strong>WARNING:</strong> Changing advanced settings can be harmful to the stability, security, and performance of this node and potentially the entire mesh network.<br><strong>You should only continue if you are sure of what you are doing.</strong></div>\n";
print "<form method=post action=advancedconfig enctype='multipart/form-data'>\n";
print "<table width=790>\n";
print "<tr><td>\n";
navbar("advancedconfig");
print "</td></tr>\n";

print "<tr><td align=center><a href='/help.html#advancedconfig' target='_blank'>Help</a>&nbsp;&nbsp;";
print "<input type=submit name=button_reboot value=Reboot style='font-weight:bold' title='Immediately reboot this node'>";
print "&nbsp;&nbsp;<input type=submit name=button_firstboot value='Reset to Firstboot' onclick=\"return confirm('All config settings and add-on packages will be lost back to first boot state. Continue?')\"  title='Reset this node to the initial/firstboot status and reboot.'>";
print "</td></tr>\n";

if(@msg)
{
  foreach(@msg)
  {
    print "<tr><td align='center'><strong>$_</strong></td></tr>\n";
  }
}

print "<tr><td align=center>\n";
print "<table border=1>\n";
print <<EOF;
    <thead>
      <tr>
        <th>Help<br><small>(hover)</small></th>
        <th>Config Setting</th>
        <th>Value</th>
        <th>Actions</th>
      </tr>
    </thead>
EOF

$scount = 0;
foreach(@setting)
{
  # check to see if setting is conditional
  if($setting[$scount]->{'condition'})
  {
    if (!eval $setting[$scount]->{'condition'})
    {
      $scount++;
      next;
    }
  }
  $sconfig = $_->{'key'};
  $sval = `uci -q get '$sconfig'`;
  print <<EOF;
      <tr>
          <td align="center"><span title="$setting[$scount]->{'desc'}"><img src="/qmark.png" /></span></td>
          <td>$sconfig</td>
          <td>
EOF

  print "<input type='text' id='field_$scount' name='newval_$scount' size='65' value='$sval'>" if($setting[$scount]->{'type'} eq "string");
  print "OFF<label class='switch'><input type='checkbox' id='field_$scount' name='newval_$scount' value='1' checked><span class='slider round'></span></label>ON" if($setting[$scount]->{'type'} eq "boolean" and $sval == 1 );
  print "OFF<label class='switch'><input type='checkbox' id='field_$scount' name='newval_$scount' value='1'><span class='slider round'></span></label>ON" if($setting[$scount]->{'type'} eq "boolean" and $sval == 0 );
  print "Click EXECUTE button to trigger this action<input type='hidden' id='field_$scount' name='newval_$scount' value='$sval'>" if($setting[$scount]->{'type'} eq "none");

  print <<EOF;
          </td>
EOF
  if($setting[$scount]->{'type'} ne "none")
  {
    print "<td align='center'><input type='submit' name='button_save_$scount' value='Save Setting' /><br><br>";
  } else {
    print "<td align='center'><input type='submit' name='button_save_$scount' value='Execute' /><br><br>";
  }

  print "<input value='Set to Default' type='button' onclick=\"document.getElementById('field_$scount').value='$setting[$scount]->{'default'}';\">" if($setting[$scount]->{'type'} eq "string");
  print "<input value='Set to Default' type='button' onclick=\"return toggleDefault('field_$scount', '$setting[$scount]->{'default'}' );\">" if($setting[$scount]->{'type'} eq "boolean");
  print <<EOF;
          </td>
      </tr>
EOF

  $scount++;
}

print "</table>\n";
print "</td></tr>\n";
print "</table>\n";

print "</form>\n";
print "</center>\n";

show_debug_info();
show_parse_errors();

page_footer();
print "</body>\n";
print "</html>\n";
