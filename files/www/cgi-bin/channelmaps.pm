=for comment

  Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2015 Conrad Lara
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

use perlfunc;

#############################

#
# @returns all channels, or specific band lis
sub rf_channel_map
{
    %channellist = (
        '900' => {
            4  => "(907)",
            5  => "(912)",
            6  => "(917)",
            7  => "(922)",
        },
        '2400' => {
            -2 => "-2 (2397)",
            -1 => "-1 (2402)",
            1  => "1 (2412)",
            2  => "2 (2417)",
            3  => "3 (2422)",
            4  => "4 (2427)",
            5  => "5 (2432)",
            6  => "6 (2437)",
            7  => "7 (2442)",
            8  => "8 (2447)",
            9  => "9 (2452)",
            10 => "10 (2457)",
            11 => "11 (2462)",
        },
        '3400' => {
             76 => "(3380)",
             77 => "(3385)",
             78 => "(3390)",
             79 => "(3395)",
             80 => "(3400)",
             81 => "(3405)",
             82 => "(3410)",
             83 => "(3415)",
             84 => "(3420)",
             85 => "(3425)",
             86 => "(3430)",
             87 => "(3435)",
             88 => "(3440)",
             89 => "(3445)",
             90 => "(3450)",
             91 => "(3455)",
             92 => "(3460)",
             93 => "(3465)",
             94 => "(3470)",
             95 => "(3475)",
             96 => "(3480)",
             97 => "(3485)",
             98 => "(3490)",
             99 => "(3495)",
        },
        '5500' => {
             37 => "36 (5190)",
             40 => "40 (5200)",
             44 => "44 (5220)",
             48 => "48 (5240)",
             52 => "52 (5260)",
             56 => "56 (5280)",
             60 => "60 (5300)",
             64 => "64 (5320)",
            100 => "100 (5500)",
            104 => "104 (5520)",
            108 => "108 (5540)",
            112 => "112 (5560)",
            116 => "116 (5580)",
            120 => "120 (5600)",
            124 => "124 (5620)",
            128 => "128 (5640)",
            132 => "132 (5660)",
            136 => "136 (5680)",
            140 => "140 (5700)",
            149 => "149 (5745)",
            153 => "153 (5765)",
            157 => "157 (5785)",
            161 => "161 (5805)",
            165 => "165 (5825)",
         },
        # 5800 UBNT US Band
        '5800ubntus' => {
            133 => "133 (5665)",
            134 => "134 (5670)",
            135 => "135 (5675)",
            136 => "136 (5680)",
            137 => "137 (5685)",
            138 => "138 (5690)",
            139 => "139 (5695)",
            140 => "140 (5700)",
            141 => "141 (5705)",
            142 => "142 (5710)",
            143 => "143 (5715)",
            144 => "144 (5720)",
            145 => "145 (5725)",
            146 => "146 (5730)",
            147 => "147 (5735)",
            148 => "148 (5740)",
            149 => "149 (5745)",
            150 => "150 (5750)",
            151 => "151 (5755)",
            152 => "152 (5760)",
            153 => "153 (5765)",
            154 => "154 (5770)",
            155 => "155 (5775)",
            156 => "156 (5780)",
            157 => "157 (5785)",
            158 => "158 (5790)",
            159 => "159 (5795)",
            160 => "160 (5800)",
            161 => "161 (5805)",
            162 => "162 (5810)",
            163 => "163 (5815)",
            164 => "164 (5820)",
            165 => "165 (5825)",
            166 => "166 (5830)",
            167 => "167 (5835)",
            168 => "168 (5840)",
            169 => "169 (5845)",
            170 => "170 (5850)",
            171 => "171 (5855)",
            172 => "172 (5860)",
            173 => "173 (5865)",
            174 => "174 (5870)",
            175 => "175 (5875)",
            176 => "176 (5880)",
            177 => "177 (5885)",
            178 => "178 (5890)",
            179 => "179 (5895)",
            180 => "180 (5900)",
            181 => "181 (5905)",
            182 => "182 (5910)",
            183 => "183 (5915)",
            184 => "184 (5920)",
         },
    );

    my($reqband) = @_;

    if ( defined($reqband) ){
         if ( exists($channellist{$reqband}) ){
             return $channellist{$reqband};
         }
         else
         {
             return -1;
         }
    }
    else {
        return $channellist;
    }
}

sub is_channel_valid
{
    my ($channel) = @_;

    if ( !defined($channel) ) {
        return -1;
    }

    $boardinfo=hardware_info();
    #We know about the band so lets use it
    if ( exists($boardinfo->{'rfband'}))
    {
        $validchannels=rf_channel_map($boardinfo->{'rfband'});

        if ( exists($validchannels->{$channel}) )
        {
            return 1;
        } else {
            return 0;
        }
    }
    # We don't have the device band in the data file so lets fall back to checking manually
    else {
        my $channelok=0;
        my $wifiintf = get_interface("wifi");
        foreach (`iwinfo $wifiintf freqlist`)
        {
            next unless /Channel $channel/;
            next if /\[restricted\]/;
            $channelok=1;
        }
        return $channelok;
    }

}


sub rf_channels_list
{

    $boardinfo=hardware_info();
    #We know about the band so lets use it
    if ( exists($boardinfo->{'rfband'}))
    {
        if (rf_channel_map($boardinfo->{'rfband'}) != -1 )
        {
            return rf_channel_map($boardinfo->{'rfband'});
        }
    }
    else
    {          
        my  %channels = ();
        my $wifiintf = get_interface("wifi");
        foreach (`iwinfo $wifiintf freqlist` )
        {
            next unless /([0-9]+.[0-9]+) GHz \(Channel ([0-9]+)\)/;
            next if /\[restricted\]/;
            my $channelnum = $2;                                                
            my $channelfreq = $1;                                               
            $channelnum =~s/^0+//g;                                             
            $channels->{$channelnum}  = "$channelfreq GHZ" ;
        }
        return $channels;
    }
}

sub is_wifi_chanbw_valid
{
    # chan_bw valid
    return 1;
}


sub rf_default_channel
{

    my %default_rf = (
        '900' => {
            chanbw  => "5",
            channel => "5",
        },
        '2400' => {
            chanbw  => "10",
            channel => "-2",
        },
        '3400' => {
            chanbw  => "10",
            channel => "84",
        },
        '5800ubntus' => {
            chanbw  => "10",
            channel => "149",
        },
    );

    $boardinfo=hardware_info();
    #We know about the band so lets use it
    if ( exists($boardinfo->{'rfband'}))
    {
        return $default_rf{$boardinfo->{'rfband'}};
    }
    else {
        # Somewhat "expensive" in that it duplicates calls made above, but rare to be used. 
        my $channels = rf_channels_list(); 
        foreach $channelnumber (sort {$a <=> $b} keys %{$channels}) {
            return { chanbw => "5", channel => $channelnumber };
        }
    }
} 
#weird uhttpd/busybox error requires a 1 at the end of this file
1

