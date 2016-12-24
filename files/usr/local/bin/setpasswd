#!/usr/bin/perl -w
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

unless(defined ($pw = shift))
{
  print STDERR "\nusage: setpasswd <password>\n";
  print STDERR "this sets both the system and website paswords\n\n";
  exit 1;
}

$pw2 = $pw;
$pw2 =~ s/'/'\\''/g;
system "{ echo '$pw2'; sleep 1; echo '$pw2'; } | passwd > /dev/null\n";

print STDERR "passwords changed.\n";
