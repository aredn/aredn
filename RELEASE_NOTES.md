__RELEASE NOTES__

# 3.22.12.0

Since version 3.22.8.0 was released in August, over 50 nightly builds have been released. So the dev team decided that it was time for another production release. While many of them were small tweaks, some were significant. Here’s a summary:

## UI (web page) updates.

Many updates were made to the UI (web pages) to increase usability and provide additional information. Some highlights:
 
* Added NTP update period to basic setup page - can now choose between daily and hourly updates    
* Now display host totals rather than OLSR totals     
* Added search capabilities to the Mesh Status page     
* Grouped Mesh RF info if WiFi is enabled     
* Both types of gateways on Status page now displayed    
* Added a warning when attempting to add extra packages to 32 MB nodes 
* Added help link to pages missing it.
* Changed support link to button
* Updated help file for new Advanced Config format
* Simplified Advanced Config display
* Added units to Setup and Advanced Config pages

## Miscellaneous fixes and updates
 
* Optionally include static routes (and preserve them across upgrades)     
* Added support for extra network links to OLSR     
* Included wireguard packages in the repo
* Fixed recoverymode script (didn't work correctly)
* Stopped a node from including itself in its LQM neighbors
* Fixed bad match for NAT DHCP addresses.
* Added a wifi scan trigger for when the "nodes detected" count becomes zero (resets wifi)
* Added a snapshot of hostnames after OLSR updates so we have a consistent copy to display on Mesh Status page
* Advertised services:
    * Determination logic updated
    * Added more 3XX redirects + 401 authentication
    * If redirect ends at an https link, assume it is valid

# 3.22.8.0

The AREDN development team has shifted into high gear with this third release of 2022!  This production release adds the many fixes and enhancements made since 3.22.6.0

## Fixes

* Dealt with LAN on AR300M always having the same MAC address.
* Fixed default DHCP limits in NAT mode if fields are blank.
* Fixed a "do not propagate" issue when reserving DHCP names.
* Fixed tactical names.
* Fully validate node and tactical names; give better messages when invalid.
* Prevent < and > from being used in service names.
* Correct map update claiming success when it actually fails.
* Added device definition for Ubiquiti PBE M5 300-ISO.
* Some Ubiquiti Powerbeams: keep 100MB as the only port speed, but let the port auto-negotiate with the switch to fix throughput issues.
* Fixed display of unknown radio models.

## Enhancements

* Added a service alert icon.
* Adjusted the Administration page display. (advanced WAN moved to AdvConfig page)
* Added changeable WAN VLAN support to the Mikrotik hAP and AR300M.
* Allowed display of longer filenames (wider field).
* Now run an hourly check on published service and “unpublish” any which aren’t really available.  Re-enabled services will be republished automatically.
* Added a visual indicator to show when a service is not being published.
* Made “Keep Settings” more prominent.
* Renamed Support Data file extension from tgz to gz (to allow them to be easily added to a forum post and/or github issues).
* Allow zero length WAN WiFi client passphrases.
* Allow LQM auto-distance to be overridden.
* Further improvements in LQM.
* Password visibility toggles on setup page.
* Added connection status feedback when using WAN WiFi.
* Status page now shows if you’re using wired or WiFi WAN.
* Updated the HTML Help file to reflect these changes.

# 3.22.6.0

AREDN production release 3.22.6.0 is now available.  This is the release you've been looking for :-)

Since the last production release, there have been 136 separate ‘pull requests’ in the AREDN github repository.   Those requests pulled these significant improvements and new features into the AREDN software:
1. The conversion from Perl programming to Lua is complete - the result is a significantly smaller, somewhat faster, code base.

2. Due to the recovered space in the image, tunnels are now always installed, so nothing needs to be done with them during future upgrades.

3. After this upgrade, future upgrades should be much more reliable, especially on low memory devices.

4. Tunnels will be prevented from accidentally connecting over the mesh.

    Tunnels normally connect via the WAN interface, that being the point of the things. However, if the WAN interface on a node goes down for some reason (the tunnel server/client Internet fails) the node will select a new way to talk to the Internet by first routing over the Mesh. When this happens, tunnels could end up being routed partially over the mesh, which is bad because tunnels are also part of the mesh. So, we now prevent this by default by adding a firewall rule.


5. You can now adjust the poll rate for alerts. AREDN alerts and local alerts (those yellow banner things you see sometimes) were polled twice a day. This is now configurable.

6. There is now a 60-second timeout when tunnel connections are interrupted. 

    Node tunnels run over TCP/IP so they guarantee that what is sent is what will be received. This is all fine when things are running reliably, but if a connected tunnel fails for a bit, but then recovers, this guarantee means very old, pending traffic will still be delivered. In AREDN’s case, this traffic is not useful to the user, and for OLSR it is positively dangerous to deliver ancient routing information. This is all low level protocol stuff and there will be no visible effects to users.


7. Nodes which are only connected via the WAN port and tunnels (no Wifi, no LAN) can cause some configuration problems because AREDN really wants either the LAN port to be connected or the WiFI to be enabled. We made some changes, so this is no longer a requirement. Thanks to K1KY, who has some unusual setups, for finding this.

8. Automatic NTP sync - we now locate an NTP server (either the one configured or by searching the mesh for a local one) and sync the time daily.

9. Added the ability to change the default VLAN for the WAN port. Currently not available on devices which contain network switches.

10. Included iperf3 by default, as well as a simple web UI. Its use is described here in the AREDN online docs.

11. Updated the Advanced Configuration page; sorted items on the page into categories.

12. Added the capability of loading firmware updates "locally" after copying them to the node via SCP.  This is useful if you’re trying to update a distant node over marginal links.   Information on how to use it is in the AREDN online docs, here.

13. Nodes will now drop nodenames and services that haven't been included in a broadcast for approximately 30 minutes.

14. The hardware brand and model have been added to the main page.

15. Messages banner will only be displayed on the Status & Mesh pages, keeping the setup & admin pages uncluttered.

16. Channels -3 and -4 have been added to 2 GHz, for use in those countries where it’s legal.

17. Added link quality management (LQM). It’s designed to make the AREDN network more stable and improve the available bandwidth.    

    When enabled LQM accomplishes this in two ways:
First, it drops links to neighbors which won't work well. Links are dropped that don't have good SNR, are too far away, or have low quality (forcing retransmissions).
Second, it uses the distance to the remaining links to optimize the radio which improves the bandwidth. This mechanism replaces the older ‘auto-distance’ system which was often confused by distant nodes with which it could barely communicate.


Many LQM parameters are capable of being modified to allow for local network circumstances.  There’s documentation on LQM in both the node help file and in the AREDN on-line docs.

**NOTE 1:** LQM is turned off by default, unless it was previously enabled in a nightly build.

**NOTE 2:** Latitude and longitude need to be configured in order for LQM to work properly.
 
**IMPORTANT NOTE:** If you’re running MeshChat and/or iPerfSpeed, after this upgrade you’ll need to install compatible versions of them (but note that with the built-in throughput test you may no longer need iPerfSpeed).  URLs for those versions:

iperfSpeed: https://github.com/kn6plv/iperfspeed/raw/master/iperfspeed_0.6-lua_all.ipk

MeshChat: https://github.com/kn6plv/meshchat/raw/master/meshchat_2.0_all.ipk

# 3.22.1.0

This release includes many significant improvements in the underlying OpenWRT code and stability/scalability fixes to the OLSR mesh routing protocol.
 
## List of Changes:
​
1. The AREDN  simplified firmware filename standard has been changed to the default OpenWRT convention to leverage data files created at build time for future automation of firmware selection.

    When installing this firmware release, from prior firmware versions, you may get an error message similar to

        “This filename is NOT appropriate for this device.“
        “This device expects a file such as: aredn-3.22.1.0-main-ef2d605-ubnt-nano-m-xw-.*sysupgrade.bin”
        “Click OK to continue if you are CERTAIN that the file is correct”

    Ensure that you are loading the correct file by referring to the downloads page, then safely ignore the warning.   Once this release is loaded, this error message will never occur again.

2. When the size of the hostname and service advertisements exceeded the size of a single network packet, only IP addresses would be known.  The advertised services and hostname would not propagate to other nodes on the network.  The OLSR routing protocol was changed to fix this.

3. The OLSR scalability failure, commonly called “OLSR storms”, has been fixed.  Large networks with hundreds of nodes would experience cycles of routing disruption, making the network unusable.  

4. SNR history may be missing neighbor node names – fixed.

5. When defining a local location of packages in Advanced Configuration, there was no way to change the location of some packages obtained from the upstream Freifunk group.    The Advanced Configuration page now has a row to define this local location.

6. Performance improvements were made to the Mesh Status page based on results from the large scale stress test on Oct 31, 2021.

7. Local alerts as configured on the Advanced Configuration page can now have zones which allow a mesh user to subscribe to alert messages affecting a specific locale.

8. The allowed number of tunnel connections is now configurable on the Advanced Configuration page.

9. There are numerous API updates.

# 3.21.4.0

This release contains, among other things the following changes and fixes:

* Fix spike to zero in SNR Chart #90 (ab7pa)
* Execute Button Description #86 (ab7pa)
* Add Rocket XM ar71xx image to support older models with USB port #83 (ae6xe)
* Fix tunnel server clients accidentally limited to 9 #82 (pmilazzo)
* Add “none” type advanced config options to simplify the UI #81 (dman776)
* Update banner #80 (dman776)
* update login banner #79 (dman776)
* Add mesh gateway setting to sysinfo.json #77 (dman776)
* Add advanced config option to purge AREDN Alert msgs #76 (dman776)
* Update alert banner background color #72 (ab7pa)
* Reset download paths upon upgrade to default #69 (dman776)
* Upgrade to openwrt 19.07.7 #68 (ae6xe)
* Add new Mikrotik model string for SXTsq5nD #62 (ae6xe)

# 3.20.3.1

The AREDN® team is pleased to announce the general availability of the latest stable release of AREDN firmware. We now fully support 70+ devices from four manufacturers. This diversity of supported equipment enables hams to choose the right gear for a given situation and budget.

Here is a summary of the significant changes since 3.20.3.0 was release:

* Migrate all remaining TP-Link models to ath79 target
* Fix CPE510 v3 image not installing
* Fix Ethernet port to fully conform with AREDN expected usage on NanoStation M5 XW
* Added ability to change and revert firmware and package download paths
* Added target type info (ar71xx/ath79) to admin page
* Fix issue with the map on the setup page PR #501
* Added "aredn alerts" feature in header
* Fix firewall blocking traffic when using tunnel PR #524
* Added support for Mikrotik r2 hardware
* Bump to OpenWRT 19.07.3 https://openwrt.org/releases/19.07/notes-19.07.3
* Use "mode ether" for tunnel links reducing ETX to 0.1
* Change default map tile server url away from MapBox PR #527
* Allow ping from WAN to node

# 3.20.3.0

The AREDN team is pleased to announce the general availability of the latest stable release of AREDN firmware. We now fully support 70+ devices from four manufacturers. This diversity of supported equipment enables hams to choose the right gear for a given situation and budget.

AREDN firmware is now based on the most recent stable version of OpenWRT19.07.2 which was released in March 2020. This improvement is significant in that it enables AREDN firmware to benefit from the many bug fixes, security improvements and feature enhancements provided by OpenWRT developers from around the world.

The latest AREDN firmware contains features inherited from the newest OpenWRT upstream release (19.07.2). One important change is the inclusion of a new target (architecture) for the firmware, labelled “ath79”, which is the successor to the existing “ar71xx” targets. OpenWRT explains that their main goal for this target is to bring the code into a form that will allow all devices to run a standard unpatched Linux kernel. This will greatly reduce the amount of customization required and will streamline the firmware development process. As not all supported devices have been migrated to the new “ath79” target, AREDN continues to build firmware for both targets.  You may notice that the AREDN download page has firmware for these two targets, and you should select the latest image based on the type of hardware (and the recommended target) on which it is to be installed. 

## Changes to the Supported Platform Matrix

Several devices are now shaded in light green to indicate that they are no longer recommended for AREDN firmware, primarily due to their low computing resources (memory/storage).

The following new devices are newly supported in the latest firmware release.

## GL.iNet

* AR750 definitions #425 (ae6xe)

* AR300M16 #419 (ae6xe)

* USB150 Microuter #411 (ae6xe)

* AR150 #407 (ZL2WRW)

## Mikrotik

* RB911G-2HPnD mANTBox #464 (ae6xe)

* RBSXTsq2nD #461 (ae6xe)

* SXTsq 2nD #458 (ae6xe)

* RBSXTsq5nD #453 (ae6xe)

* RBSXTsq5HPnD #446 (ae6xe)

* LDF-2nD, LHG-2nD, LHG-2nD-XL #436 (ae6xe)

* New LDF5 model number #410 (ae6xe)

* LHG 5HPnD #395 (ae6xe)

## TP-LINK
CPE210 v3.1 and v3.2 #484 (ae6xe)

WBS510 V2 #466 (apcameron)

## Features added

* Upgraded to pre-openwrt-19.07.2 #487 (ae6xe)

* Added /etc/board.json to aredn support data download #483 (ae6xe)

* Added contact info/comment field for each tunnel connect… #479 (r1de)

* Removed libopenssl (large library) and disable ssl in vtun #475 (dman776)

* Common build config updates #467 (ae6xe)

* Reduce visual clutter on mesh status page #459 (kostecke)

* Removed the meshmap=1 option from sysinfo.json. #454 (r1de)

* Updated Help for passive Wifi Scan updates #445 (ae6xe)

* Switch from active to passive wifi scan #444 (ae6xe)

* Updated with note regarding gl.inet keep settings #440 (dman776)

* Added olsr restart option in AdvancedConfig #435 (ae6xe)

* Enabled wan wifi client to connect to an open AP #434 (ae6xe)

* Added wan wifi client capability #430 (ae6xe)

* Check less frequently to updated Mesh link LED #422 (ae6xe)

* Added “MESH” led for GL USB150 #417 (dman776)

* Added first_boot field to indicate if this node has been configured #416 (dman776)

* Added auto distance setting option #409 (ae6xe)

* New sysinfo json changes #405 (r1de)

* Fixed the consistency between “archive” and “realtime” SNR data #403 (mcleanra)

* Updated .gitnignore to ignore more build artifacts #402 (BKasin)

* Minor UI/output updates #399 (BKasin)

* Set default channel and width #396 (ae6xe)

* API - added current dhcp leases #394 (dman776)

* Added localhosts info to api #390 (mcleanra)

* Added OLSR current neighbor info to API #389 (dman776)

* Added chart endpoint to the /api #386 (mcleanra)

* Added a wifi scan endpoint to the /api #379 (mcleanra)

## Bugs fixed

* PBE400/400-ISO/620 port hang #493 (ae6xe)

* Changed firmware download location #488 (dman776)

* Port Forward not working over dtdlink in LAN NAT mode #485 (ae6xe)

* Added missing network definitions for GL-AR150 #482 (ae6xe)

* ath79 TP-Link CPE210 v2 changed name #481 (ae6xe)

* Fixed the Authentication for vtun to be compatible with legacy #478 (apcameron)

* Fixed status led for the WBS510-v2 #476 (apcameron)

* +x to /www/cgi-bin/mesh - 403 error if not. #460 (r1de)

* WAN interface fails to function on UBNT NS XM devices #433 (ae6xe)

* Fixed instance of sysupgrade failing #432 (ae6xe)

* Mesh Status missing owning host of service advertisement #421 (ae6xe)

* Added build config for AR300M #420 (ae6xe)

* Fixed index error in aredn_info lib #412 (dman776)

* Fixed call to getFrequency() to getFreq() in api #408 (r1de)

* UBNT LBE-M5 does not identify boardid #401 (ae6xe)

* Added luasocket feed to make luasocket package available #391 (dman776)

## Known issues
Please refer to https://github.com/aredn/aredn_ar71xx/issues for a list of outstanding defects.

## Key workarounds

### OLSR Restart

OLSR is the capability in AREDN that exchanges IP Addresses, Hostnames, and figures how to route packets across the mesh network.   There continues to be an intermittent defect when OLSR starts as a device is powering up. OLSR fails to propagate or may miss receiving some hostname information.  A one-time restart of OLSR will resolve the situation. This option can be found in Advanced Configuration settings--it doesn’t save a setting per se, rather restarts OLSR without rebooting the device.  

How do I know when OLSR needs to be restarted:

* IP Address is showing in Mesh Status:  go to the IP Address’s node and restart OLSR

* “Dtdlink” or “mid” is showing in a host name:  go to those hosts and restart OLSR

* Others can access a device by the hostname, but I can’t:  restart OLSR on my device

### PBE 400/400-ISO/620 degraded throughput over ethernet port

These Uniquiti PBE devices have a gigabit Ethernet port that does not handshake correctly with some switches.   The device’s Ethernet port is locked to a 100mbps rate at Full-Duplex (still sufficient for the max rates generally achieved over RF).  This made the port always functional, but for some switches the performance may be severely degraded. It is recommended to lock the rate on all switches this devices is connected to at the same 100mbps rate at Full-Duplex.  Check your switch’s port statistics to determine if there are TX or RX packet errors. Alternatively, an iperf test from the node to another node on the same switch will identify if there is any performance degradation.

### Upgrading Firmware Images

1) 32M RAM devices continue to be at the limit of available memory.  This means that doing a sysupgrade to load new firmware may take many tries to succeed.   Don't use these devices at hard to reach tower sites! The sysupgrade process needs close to 10M of memory to succeed. 

    **Tips to get it to work:**

    1) fresh reboot and very quickly do the upgrade (recommended for all devices, particular if at a tower site)

    2) disable mesh RF and any use of wireless, reboot before sysupgrade

    3) disable or uninstall any packages that are running, e.g. meshchat

    4) as an almost last resort, scp the .bin image to /tmp on the node and from the command line type "sysupgrade -n <.bin filename>" (does not save settings)

    5) as the last resort, tftp to load the factory image (does not save settings) 

2) Do not count on being able to sysupgrade to return back to older AREDN images, when upgrading to ‘ath79’ target images.    It might work, it might not based on if model names were cleaned up and changed moving to ath79. The older images may not be recognized on the newer target images.  Do a tftp process instead.

3) To know what image to use, pay close attention to the table located here (scroll down):  https://github.com/aredn/aredn_ar71xx .
