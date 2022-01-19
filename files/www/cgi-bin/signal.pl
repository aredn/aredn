#!/usr/bin/perl
=for comment

  Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2015 Darryl Quinn
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

chomp ($tzone=`date +%Z`);
read_query_string();

# collect some variables
$node = nvram_get("node");
$node = "NOCALL" unless $node;

if($parms{"realtime"} )
{
  $dmode="Realtime";
} else {
  $dmode="Archived";
}

http_header();
html_header("$node $dmode signal strength", 0);

$header = <<EOF;
  <link href="/loading.css" rel="stylesheet">
  <script src="/js/jquery-2.1.4.min.js"></script>
  <script src="/js/jquery.canvasjs.min.js"></script>
  <script type="text/javascript">
    var dps=[[{"label":"Init","y":[-95,-95]}]];

    // Read a page's GET URL variables and return them as an associative array.
    function getUrlVars()
    {
        var vars = [], hash;
        var hashes = window.location.href.slice(window.location.href.indexOf('?') + 1).split('&');
        for(var i = 0; i < hashes.length; i++)
        {
            hash = hashes[i].split('=');
            vars.push(hash[0]);
            vars[hash[0]] = hash[1];
        }
        return vars;
    }

    function hide_spinner() {
      \$('#content-loading-spinner').dequeue();
      \$('#content-loading-spinner').hide();
      \$('#content-overlay').dequeue();
      \$('#content-overlay').hide();
    }

    \$(document).ajaxComplete(function() {
      hide_spinner();
    });

    \$(document).ready(function () {
      var MAXPOINTS=10;
      var chart = new CanvasJS.Chart("chartContainer", {
        zoomEnabled: true,
        zoomType: "xy",
        exportEnabled: true,
        backgroundColor: "#E7E7E7",
        title: {
          text: "$dmode Signal to Noise"
        },
        legend: {
          horizontalAlign: "right", // left, center ,right
          verticalAlign: "center",  // top, center, bottom
        },
        axisX: {
           title: "Time (in $tzone)",
           labelFontSize: 12,
           labelAngle: -45,
           valueFormatString: "MM/DD HH:mm",
        },
        axisY: {
          title: "dBm",
          interlacedColor: "#F0F8FF",
        },
        toolTip: {
          contentFormatter: function (e) {
            var content = " ";
            content += "At " + e.entries[0].dataPoint.timestamp.substring(11, 19) + "<br />";
            if (e.entries[0].dataPoint.signal_dbm) {
               content += "Signal: " + e.entries[0].dataPoint.signal_dbm + "dBm<br/>";
            } else {
               content += "Signal: 0<br/>";
            }
            content += "Noise: " + e.entries[0].dataPoint.noise_dbm + "dBm<br/>";
            content += "SNR: " + e.entries[0].dataPoint.snr + "dB<br/>";
            content += "TX Rate: " + e.entries[0].dataPoint.tx_rate_mbps + "Mbps<br/>";
            content += "TX MCS: " + e.entries[0].dataPoint.tx_rate_mcs_index + "<br/>";
            content += "RX Rate: " + e.entries[0].dataPoint.rx_rate_mbps + "Mbps<br/>";
            content += "RX MCS: " + e.entries[0].dataPoint.rx_rate_mcs_index + "<br/>";
            return content;
          }
        },
        data: [
          {
            type: "rangeArea",
            xValueType: "dateTime",
            showInLegend: true,
            legendText: "Signal",
            dataPoints: dps[0]
          }
        ],
      }); // --- chart

      var formatDataPoint = function(point) {
          point.label = point.timestamp.substring(5, 10) + " " + point.timestamp.substring(11, 19);
          point.y = [point.signal_dbm, point.noise_dbm];
          point.snr = (point.noise_dbm * -1) - (point.signal_dbm * -1);
          point.tx_rate_mcs_index = point.tx_rate_mcs_index ? point.tx_rate_mcs_index : "N/A";
          point.rx_rate_mcs_index = point.rx_rate_mcs_index ? point.rx_rate_mcs_index : "N/A";
          return point;
      };

      var updateArchiveChart = function () {
        \$.getJSON("/cgi-bin/api?chart=archive&device=$parms{device}", function (result) {
          var points = result.pages.chart.archive.map(formatDataPoint);
          chart.options.data[0].dataPoints = points;
          if(result.pages.chart.archive.constructor === Array) {
            chart.render();
          };
        });
      };

      var updateRealtimeChart = function () {
        \$.getJSON("/cgi-bin/api?chart=realtime&realtime=1&device=$parms{device}", function (result) {
          var point = formatDataPoint(result.pages.chart.realtime[0]);
          dps[0].push(point);
          chart.render();
          toneFreq(point.snr);
          \$('#snr').html(point.snr);
        });
      };

      var dmode = getUrlVars()["realtime"];

      if(dmode) {
        updateRealtimeChart();
        setInterval(function() {updateRealtimeChart()}, 1000);
      } else {
        updateArchiveChart();
        setInterval(function() {updateArchiveChart()}, 60000);
      }
      chart.render();
    }); // --- document.ready

    var audioCtx = new(window.AudioContext || window.webkitAudioContext)();
    var oscillator = audioCtx.createOscillator();
    var gainNode = audioCtx.createGain();
    oscillator.connect(gainNode);
    oscillator.type = 'sine';
    gainNode.connect(audioCtx.destination);
    gainNode.gain.value = 1;

    function toneFreq(snr) {
      var p = document.getElementById("tonePitch").value;
      oscillator.frequency.value = snr * p;  
      var v = document.getElementById("toneVol").value;
      gainNode.gain.value = v;
    }

    function toneOn() { 
      oscillator = audioCtx.createOscillator();
      gainNode = audioCtx.createGain();
      oscillator.connect(gainNode);
      oscillator.type = 'sine';
      gainNode.connect(audioCtx.destination);
      gainNode.gain.value = .5; 
      oscillator.start();
      document.getElementById("toneOff").disabled = false;
      document.getElementById("toneOn").disabled = true;
    };

    function toneOff() {
      document.getElementById("toneOff").disabled = true;
      document.getElementById("toneOn").disabled = false;
      oscillator.stop();
    };

  </script>
  </head>
EOF

$page = <<EOF;
<body>
  <div class="overlay" id="content-overlay"></div>
  <div id="content-loading-spinner-wrapper">
    <div id="content-loading-spinner">
        <div class="spinner"></div>
        <div class="loading-text">
            Loading . . .
        </div>
    </div>
  </div>
  <center>
    <div class="TopBanner">
      <div class="LogoDiv"><img src="/AREDN.png" class="AREDNLogo"></img></div>
    </div>
    <h1><big>$node</big></h1><hr>
    <nobr>
    <button onclick="window.location.href='/cgi-bin/signal'">Archive</button>
    <button onclick="window.location.href='/cgi-bin/signal?realtime=1'">Realtime</button>
    <button onclick="window.location.href='/cgi-bin/status'">Quit</button>
    <br />
    <div id="deviceSelector">
    <form name="deviceSelector" method="GET" action="/cgi-bin/signal">
    Selected Device:&nbsp;<select name="device" onChange="this.form.submit();">
EOF

# get a list of files from /tmp/snrlog
my @files = `ls -1A /tmp/snrlog`;
$parms{device}="" if(!/$parms{device}/ ~~ @files);

# default to "Strongest Signal" for Realtime
if(! $parms{device} and $parms{realtime}) {
  $page = $page . "<option selected value='strongest'>Average signal for all connected stations</option>";
}

$firstSel=1;
# iterate over each file
foreach $logfile (@files)
{
  chomp($logfile);
  my ($dmac, $dname) = $logfile =~ /^(.*?)\-(.*)/;
  $dname=$dmac if($dname eq '');
  if($parms{device} eq $logfile or (!$parms{realtime} and $firstSel)) {
    $page = $page . "<option selected value='$logfile'>$dname</option>\n";
    $firstSel=0;
  } else {
    $page = $page . "<option value='$logfile'>$dname</option>\n";
  }
}

$page = $page . "</select>\n";
$page = $page . "<input type='hidden' name='realtime' value='1'></input>\n" if($parms{realtime} eq "1");
$page = $page . <<EOF;
    </form>
    </div>
    <div id="snrValues" style="float: left;">
EOF
$page = $page . "<div><h3>SNR: <span id='snr'>0</span>dB</h3></div>" if($parms{"realtime"} eq "1");
if($parms{"realtime"} eq "1") {
  $page = $page . "<div style='float: right;'>Sound: <button id='toneOn' onclick='toneOn();'>On</button>&nbsp;";
  $page = $page . "<button id='toneOff' disabled onclick='toneOff();'>Off</button><br /><br />";
  $page = $page . "Pitch:&nbsp;<input type='range' id='tonePitch' name='tonePitch' min='5' max='100'></input><br /><br />";
  $page = $page . "Volume:&nbsp;<input type='range' id='toneVol' name='toneVol' min='0' max='10'></input><br /><br />";
  $page = $page . "</div>";
}

$page = $page . <<EOF;
    </div>
    <div id="chartContainer" style="width: 80%; height: 60%;"></div>
  </center>
EOF

print $header;
print $page;
show_debug_info();
print "</body></html>";

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
