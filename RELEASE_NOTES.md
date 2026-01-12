__RELEASE NOTES__

# 4.26.1.0

This release is the first AREDN production release that omits the legacy OLSR protocol, and consequently the first release with the major number 4\. That may sound scary, but if all your local nodes are on 3.25.5.0 or greater, they already speak Babel. That means a migration to this production release should pretty much be a non-event for your network.

### Major Features

* Babel only routing. OLSR is no longer available.
* OpenWRT 24.10.5 ([https://openwrt.org/releases/24.10/notes-24.10.5](https://openwrt.org/releases/24.10/notes-24.10.5))
* Support for HaLow 900MHz radios
* Default NTP now [aredn.pool.ntp.org](http://aredn.pool.ntp.org)
* Tunnel backup and restore to simplify node migration ([https://docs.arednmesh.org/en/latest/arednGettingStarted/node\_admin.html\#tunnel-backup-restore](https://docs.arednmesh.org/en/latest/arednGettingStarted/node_admin.html#tunnel-backup-restore))
* Support for user defined files in backups and upgrades ([https://docs.arednmesh.org/en/latest/arednGettingStarted/node\_admin.html\#backup-configuration](https://docs.arednmesh.org/en/latest/arednGettingStarted/node_admin.html#backup-configuration))
* Support for new app launcher in sidebar ([https://docs.arednmesh.org/en/latest/arednHow-toGuides/app-launcher.html](https://docs.arednmesh.org/en/latest/arednHow-toGuides/app-launcher.html))
* Save AREDN node as a webapp.
* Bump the major release number to 4\.

### New Devices Supported

* Nanostation AC Loco
* Cudy TR1200
* Cudy TR3000
* HaLowLink 1
* Heltec HT-HD01
* Heltec HT-HD7608
* Alfa Tube-AHM
* Alfa Tube-AHM PoE
* Bhyve virtual machines
* VirtualBox virtual machines

### Notes

* There is still some instability with HaLow devices due to immature support for these radios in current Linux kernels. This manifests as occasional device restarts.
* HaLow devices may sometimes require power cycling after upgrading.

### Fixes and Enhancements

* Add API to publish and find services. [\#2587](https://api.github.com/repos/aredn/aredn/pulls/2587)
* Disable short preambles when we can. [\#2586](https://api.github.com/repos/aredn/aredn/pulls/2586)
* Improve MAC to IP acquisition in LQM [\#2582](https://api.github.com/repos/aredn/aredn/pulls/2582)
* Make the upgrade system use the common backup mechanism. [\#2581](https://api.github.com/repos/aredn/aredn/pulls/2581)
* Use canonical ip for tracking if simple ip is not available. [\#2580](https://api.github.com/repos/aredn/aredn/pulls/2580)
* Upgrade default ntp servers [\#2577](https://api.github.com/repos/aredn/aredn/pulls/2577)
* Add the official 'aredn.pool.ntp.org' [\#2576](https://api.github.com/repos/aredn/aredn/pulls/2576)
* Launch icons for installed apps (experimental). [\#2575](https://api.github.com/repos/aredn/aredn/pulls/2575)
* Add mechanism to let users include files in backups [\#2573](https://api.github.com/repos/aredn/aredn/pulls/2573)
* Update default NTP servers [\#2570](https://api.github.com/repos/aredn/aredn/pulls/2570)
* Protect against badly formatted wireguard configurations [\#2567](https://api.github.com/repos/aredn/aredn/pulls/2567)
* Fix password to escape *all* special characters in pattern match. [\#2564](https://api.github.com/repos/aredn/aredn/pulls/2564)
* Don't use a basename with LAN address when setting up dhcp. [\#2563](https://api.github.com/repos/aredn/aredn/pulls/2563)
* Improve the way to add new supported features. [\#2557](https://api.github.com/repos/aredn/aredn/pulls/2557)
* Improve when we display messages about poor tunnel performance. [\#2550](https://api.github.com/repos/aredn/aredn/pulls/2550)
* Protect UI from bad tunnel server ip address. [\#2547](https://api.github.com/repos/aredn/aredn/pulls/2547)
* Add some alert messaging around poorly performing tunnels [\#2546](https://api.github.com/repos/aredn/aredn/pulls/2546)
* Restart babel when we restart the network. [\#2544](https://api.github.com/repos/aredn/aredn/pulls/2544)
* Workaround for routing table \= 0 meaning default routing table [\#2539](https://api.github.com/repos/aredn/aredn/pulls/2539)
* Add default babel buffer size in as hint text [\#2529](https://api.github.com/repos/aredn/aredn/pulls/2529)
* Allow Babel protocol buffer size to be overridden [\#2528](https://api.github.com/repos/aredn/aredn/pulls/2528)
* Disable babel monitor on supernodes. [\#2526](https://api.github.com/repos/aredn/aredn/pulls/2526)
* Yank the dns regexps out of the inner loop. [\#2517](https://api.github.com/repos/aredn/aredn/pulls/2517)
* Fix ssh option capitalization. [\#2516](https://api.github.com/repos/aredn/aredn/pulls/2516)
* Name wireguard config sections to wireguard watchdog tools can find them [\#2512](https://api.github.com/repos/aredn/aredn/pulls/2512)
* Fix watchdog out-of-bound array access [\#2511](https://api.github.com/repos/aredn/aredn/pulls/2511)
* Fix identification of Mikrotik v7 bootloader. [\#2508](https://api.github.com/repos/aredn/aredn/pulls/2508)
* Make sure tunnel costs can never be zero. [\#2502](https://api.github.com/repos/aredn/aredn/pulls/2502)
* Add /var/etc/babel-active.conf to support data. [\#2501](https://api.github.com/repos/aredn/aredn/pulls/2501)
* LAN/WAN firewall rules not needed here anymore. [\#2500](https://api.github.com/repos/aredn/aredn/pulls/2500)
* Improve consistency of neighbor status display [\#2496](https://api.github.com/repos/aredn/aredn/pulls/2496)
* Delay firewall restart [\#2487](https://api.github.com/repos/aredn/aredn/pulls/2487)
* Rework the tunnel config message field names to match UI. [\#2482](https://api.github.com/repos/aredn/aredn/pulls/2482)
* Upgrade to OpenWRT 24.10.3 (Babel Only Builds) [\#2481](https://api.github.com/repos/aredn/aredn/pulls/2481)
* Fix first use progress bars. [\#2476](https://api.github.com/repos/aredn/aredn/pulls/2476)
* Missing sleep after shutting down babel during upgrade. [\#2473](https://api.github.com/repos/aredn/aredn/pulls/2473)
* Fix allow range of tunnel costs [\#2472](https://api.github.com/repos/aredn/aredn/pulls/2472)
* Add a 2 minute last seen margin [\#2469](https://api.github.com/repos/aredn/aredn/pulls/2469)
* Lower min kernel memory requirement while uploading new firmware. [\#2466](https://api.github.com/repos/aredn/aredn/pulls/2466)
* Improve bad radio hardware handling in UI [\#2461](https://api.github.com/repos/aredn/aredn/pulls/2461)
* Don't override vm.min\_free\_kbytes [\#2460](https://api.github.com/repos/aredn/aredn/pulls/2460)
* Fix issues with hidden node detection [\#2456](https://api.github.com/repos/aredn/aredn/pulls/2456)
* Add free memory to sysinfo.json [\#2449](https://api.github.com/repos/aredn/aredn/pulls/2449)
* Increase timeouts when running service restarts [\#2442](https://api.github.com/repos/aredn/aredn/pulls/2442)
* Improve HTMODE selection (with thanks to [https://github.com/grozzie2](https://github.com/grozzie2)) [\#2440](https://api.github.com/repos/aredn/aredn/pulls/2440)
* Add glinet,gl-b1300 as a supernode [\#2436](https://api.github.com/repos/aredn/aredn/pulls/2436)
* Add radio mode (unused currently) to getHTMode() [\#2435](https://api.github.com/repos/aredn/aredn/pulls/2435)
* Hide supernode indicator if hardware cannot be a supernode [\#2434](https://api.github.com/repos/aredn/aredn/pulls/2434)
* Use NOHT mode on ac2/ac3 to see if this stabilizes the radios. [\#2431](https://api.github.com/repos/aredn/aredn/pulls/2431)
* Add missing gpsd packages. [\#2430](https://api.github.com/repos/aredn/aredn/pulls/2430)
* Aggressively turn down wifi high-throughput support on error. [\#2423](https://api.github.com/repos/aredn/aredn/pulls/2423)
* Improved log watch command [\#2422](https://api.github.com/repos/aredn/aredn/pulls/2422)
* Give babel time to stop before restarting [\#2418](https://api.github.com/repos/aredn/aredn/pulls/2418)
* Drop babel monitor LQ requirement to 50% [\#2416](https://api.github.com/repos/aredn/aredn/pulls/2416)
* Fix longer reboot/upgrade timer progress bar [\#2412](https://api.github.com/repos/aredn/aredn/pulls/2412)
* Make sure to run wpa\_supplicant for open stations. [\#2410](https://api.github.com/repos/aredn/aredn/pulls/2410)
* Improve selection of hostapd and wpa\_supplicant [\#2407](https://api.github.com/repos/aredn/aredn/pulls/2407)
* Add basic validation to lan and wan vlan settings [\#2405](https://api.github.com/repos/aredn/aredn/pulls/2405)
* Improve babel monitoring to eliminate false positives [\#2402](https://api.github.com/repos/aredn/aredn/pulls/2402)
* Require a perfect LQ to trigger the babel monitor restart [\#2400](https://api.github.com/repos/aredn/aredn/pulls/2400)
* Add missing ucode dependency (was being implicitly included) [\#2399](https://api.github.com/repos/aredn/aredn/pulls/2399)
* Monitor Babel and restart if necessary. [\#2396](https://api.github.com/repos/aredn/aredn/pulls/2396)
* Tidy RTT display for DtDs [\#2393](https://api.github.com/repos/aredn/aredn/pulls/2393)
* Use EFI/x86 upgrades when necessary. [\#2390](https://api.github.com/repos/aredn/aredn/pulls/2390)
* Show the correct default VLANs for WAN and LAN in Network popup. [\#2386](https://api.github.com/repos/aredn/aredn/pulls/2386)
* Add templates (Camera \+ Video) for Amcrest cameras [\#2380](https://api.github.com/repos/aredn/aredn/pulls/2380)
* Allow setting of LAN VLAN for single port devices. [\#2379](https://api.github.com/repos/aredn/aredn/pulls/2379)
* Improve location handling when map cannot be reached. [\#2371](https://api.github.com/repos/aredn/aredn/pulls/2371)
* Support HTTP preflight [\#2361](https://api.github.com/repos/aredn/aredn/pulls/2361)
* Make icon spin when loading cloud nodes in appmode. [\#2340](https://api.github.com/repos/aredn/aredn/pulls/2340)
* Provide a 307 redirect in the server for the root page. [\#2339](https://api.github.com/repos/aredn/aredn/pulls/2339)
* Improve video proxy error handling. [\#2337](https://api.github.com/repos/aredn/aredn/pulls/2337)
* Add cloud and map pages to webapp [\#2332](https://api.github.com/repos/aredn/aredn/pulls/2332)
* Add cloud and map shortcuts to manifest [\#2327](https://api.github.com/repos/aredn/aredn/pulls/2327)
* Fix math for generating M9 channel numbers. [\#2326](https://api.github.com/repos/aredn/aredn/pulls/2326)
* Add webapp manifest support. [\#2323](https://api.github.com/repos/aredn/aredn/pulls/2323)
* Improve UI around video proxy. [\#2321](https://api.github.com/repos/aredn/aredn/pulls/2321)
* Add a few more service templates. [\#2318](https://api.github.com/repos/aredn/aredn/pulls/2318)
* Improve URL parser. [\#2316](https://api.github.com/repos/aredn/aredn/pulls/2316)
* Quiet bad message pings. [\#2313](https://api.github.com/repos/aredn/aredn/pulls/2313)
* More tightening of proxies. [\#2310](https://api.github.com/repos/aredn/aredn/pulls/2310)
* Add a reminder to install ffmpeg if used without it. [\#2308](https://api.github.com/repos/aredn/aredn/pulls/2308)
* Common validation of the URLs passed to the various proxy urls. [\#2306](https://api.github.com/repos/aredn/aredn/pulls/2306)
* Improve UI around local service proxies [\#2305](https://api.github.com/repos/aredn/aredn/pulls/2305)
* Use resolv library again now file descriptor leak has been fixed. [\#2301](https://api.github.com/repos/aredn/aredn/pulls/2301)
* Add Advanced Options to let the operator restart specific services. [\#2299](https://api.github.com/repos/aredn/aredn/pulls/2299)
* Don't preserve babel state across upgrades [\#2290](https://api.github.com/repos/aredn/aredn/pulls/2290)
* Add the other missing backup message when auto selecting firmware [\#2287](https://api.github.com/repos/aredn/aredn/pulls/2287)
* Add missing backup message when auto selecting firmware. [\#2285](https://api.github.com/repos/aredn/aredn/pulls/2285)
* Ping correct download servers rather than hardwired [\#2282](https://api.github.com/repos/aredn/aredn/pulls/2282)
* Don't add the WAN default route if there isn't one. [\#2278](https://api.github.com/repos/aredn/aredn/pulls/2278)
* Add timeout to socat in case the connection hangs. [\#2277](https://api.github.com/repos/aredn/aredn/pulls/2277)
* Fix unnecessary reboot requests with user blocks. [\#2270](https://api.github.com/repos/aredn/aredn/pulls/2270)
* Change check for adhoc mode to avoid circular dependency [\#2267](https://api.github.com/repos/aredn/aredn/pulls/2267)
* Restore user blocks for all mesh types. [\#2264](https://api.github.com/repos/aredn/aredn/pulls/2264)
* Make the tunnel restore UI a little less janky. [\#2262](https://api.github.com/repos/aredn/aredn/pulls/2262)
* UI to backup and restore just the tunnel configuration. [\#2260](https://api.github.com/repos/aredn/aredn/pulls/2260)
* PTxP fixes for what memory saving broke. [\#2258](https://api.github.com/repos/aredn/aredn/pulls/2258)
* Disable wpa\_supplicant if we're not using encryption even if we need hostapd [\#2255](https://api.github.com/repos/aredn/aredn/pulls/2255)
* Preserve custom babel rules. [\#2252](https://api.github.com/repos/aredn/aredn/pulls/2252)
* Allow the ID beacon to be disabled. [\#2251](https://api.github.com/repos/aredn/aredn/pulls/2251)
* More emphatic message that downgrading from Babel-only build can ruin your life. [\#2244](https://api.github.com/repos/aredn/aredn/pulls/2244)
* Improve tunnel migration. [\#2243](https://api.github.com/repos/aredn/aredn/pulls/2243)
* Refine the portable theme so it only kicks for admin. [\#2239](https://api.github.com/repos/aredn/aredn/pulls/2239)
* Arednlink pub/sub like mechanism [\#2237](https://api.github.com/repos/aredn/aredn/pulls/2237)
* Make sure dtdlink always has an ipv6 link local address. [\#2234](https://api.github.com/repos/aredn/aredn/pulls/2234)
* Use mac address as neighbor popup title if nothing else [\#2232](https://api.github.com/repos/aredn/aredn/pulls/2232)
* Improve feature detection [\#2231](https://api.github.com/repos/aredn/aredn/pulls/2231)
* Fix create of allow/deny maclist files for PtXP modes [\#2230](https://api.github.com/repos/aredn/aredn/pulls/2230)
* Improve watchdog so it can shutdown without a reboot and you can update the firmware without disabling it [\#2227](https://api.github.com/repos/aredn/aredn/pulls/2227)
* Add Babel's RTT calculation to main display [\#2226](https://api.github.com/repos/aredn/aredn/pulls/2226)
* Fix 3GHz setup being set to wrong band [\#2225](https://api.github.com/repos/aredn/aredn/pulls/2225)
* Change the tunnel server network setup now we have no vtun [\#2223](https://api.github.com/repos/aredn/aredn/pulls/2223)
* Remove lowmem fixups we no longer need. [\#2222](https://api.github.com/repos/aredn/aredn/pulls/2222)
* Improve way we calculate routable information (for display only) [\#2221](https://api.github.com/repos/aredn/aredn/pulls/2221)
* Handle Old UI wifi migration. [\#2219](https://api.github.com/repos/aredn/aredn/pulls/2219)
* Remove old wifi keys [\#2218](https://api.github.com/repos/aredn/aredn/pulls/2218)
* Temporary fixup for nodes with bad dtdlink addresses. [\#2213](https://api.github.com/repos/aredn/aredn/pulls/2213)
* Automatically select the best firmware to upgrade to. [\#2209](https://api.github.com/repos/aredn/aredn/pulls/2209)
* Remove multicast\_querier property. [\#2208](https://api.github.com/repos/aredn/aredn/pulls/2208)
* Remove bad port forwarding rule for wan only. [\#2206](https://api.github.com/repos/aredn/aredn/pulls/2206)
* Fix memory leak in dnsmasq. [\#2204](https://api.github.com/repos/aredn/aredn/pulls/2204)
* Fix broken reboot when restoring. [\#2199](https://api.github.com/repos/aredn/aredn/pulls/2199)
* Allow LAN subnet to access WAN subnet so port forwarding will work. [\#2198](https://api.github.com/repos/aredn/aredn/pulls/2198)
* Use the DEVICE variable when setting up wan/lan routes during network setup [\#2195](https://api.github.com/repos/aredn/aredn/pulls/2195)
* Fix local access to wan subnet [\#2191](https://api.github.com/repos/aredn/aredn/pulls/2191)
* More backup and support data improvements. [\#2189](https://api.github.com/repos/aredn/aredn/pulls/2189)
* Reduce the files we keep in the backups. [\#2188](https://api.github.com/repos/aredn/aredn/pulls/2188)
* Delete old gateway keys [\#2187](https://api.github.com/repos/aredn/aredn/pulls/2187)
* Let the mesh stats open the mesh page [\#2183](https://api.github.com/repos/aredn/aredn/pulls/2183)
* Display Babel round trip time [\#2182](https://api.github.com/repos/aredn/aredn/pulls/2182)
* Fix use of old key names rather than new ones [\#2179](https://api.github.com/repos/aredn/aredn/pulls/2179)
* Provide flexible reboot/upgrade timeouts for slower devices [\#2177](https://api.github.com/repos/aredn/aredn/pulls/2177)
* Rewrite routing rules (babel edition) [\#2175](https://api.github.com/repos/aredn/aredn/pulls/2175)
* Fix calculation of 3GHz channel numbers [\#2174](https://api.github.com/repos/aredn/aredn/pulls/2174)
* Improve display of status information for babel-only supernodes. [\#2162](https://api.github.com/repos/aredn/aredn/pulls/2162)
* Enable channels 180-184 in PtXP modes [\#2157](https://api.github.com/repos/aredn/aredn/pulls/2157)
* Fix propagation of correct LAN host names. [\#2156](https://api.github.com/repos/aredn/aredn/pulls/2156)
* Improve neighbor information [\#2154](https://api.github.com/repos/aredn/aredn/pulls/2154)
* Tweak uptime description [\#2153](https://api.github.com/repos/aredn/aredn/pulls/2153)
* Make the link ip clickable. [\#2150](https://api.github.com/repos/aredn/aredn/pulls/2150)
* Provide link uptime as well as last seen time. [\#2149](https://api.github.com/repos/aredn/aredn/pulls/2149)
* Let hosts without services take whole line to improve readability [\#2136](https://api.github.com/repos/aredn/aredn/pulls/2136)
* Don't forward 172.3x.x.x to supernodes for lookups [\#2132](https://api.github.com/repos/aredn/aredn/pulls/2132)
* Allow . in cron script names [\#2131](https://api.github.com/repos/aredn/aredn/pulls/2131)
* Don’t masquerade source address for broadcast traffic [\#2129](https://api.github.com/repos/aredn/aredn/pulls/2129)
* Always show dns (if defined) rather then only when WAN is enabled [\#2126](https://api.github.com/repos/aredn/aredn/pulls/2126)
* Missing tunnel endpoint when setting up firewall [\#2123](https://api.github.com/repos/aredn/aredn/pulls/2123)
* Handle radio type of 'none' [\#2118](https://api.github.com/repos/aredn/aredn/pulls/2118)
* SNAT tunnels and xlinks so we don't redistribute their actual endpoint IPs [\#2115](https://api.github.com/repos/aredn/aredn/pulls/2115)
* Fix GPS detection [\#2111](https://api.github.com/repos/aredn/aredn/pulls/2111)

# 3.25.5.0

**Major Enhancements**

This release heralds some major changes with AREDN® and we encourage you to take a moment to read about them below,

**Babel Routing**

The AREDN® team is introducing [Babel](https://www.irif.fr/~jch/software/babel/) as a replacement for the older OLSR routing technology. OLSR has served us well, but has many problems we’ve had to live with over the years. Babel, on the other hand, has many qualities which make it a good fit AREDN®. First, it’s a loop free protocol so, regardless of how the network is changing, routing loops will never form in the network. Second, it has a   substantially lower traffic overhead so is good for slow, low bandwidth links. Third, the protocol adapts to the differences between wired, wireless, and tunneled links. Fourth, as a layer-3 routing protocol, it integrates easily with AREDN®. Fifth, it’s highly configurable. Finally, it’s simple. [This](https://www.youtube.com/watch?v=1zMDLVln3XM) video is a great primer on Babel.

In this release Babel and OLSR will run side-by-side, with Babel routing used where available, and OLSR used otherwise. No configuration is necessary. You will see a three-stars symbol on neighbors which support Babel, and a new three-stars symbol on the left-hand menu where you can see what services Babel nodes are advertising.

More on the switch to Babel can be found here: [https://docs.arednmesh.org/en/latest/arednHow-toGuides/babel.html\#adding-babel-as-an-aredn-routing-protocol](https://docs.arednmesh.org/en/latest/arednHow-toGuides/babel.html#adding-babel-as-an-aredn-routing-protocol)

**Deprecating Tiny Firmware Nodes**

This will be the last major release to support tiny firmware builds for older nodes. These older nodes have too little memory for us to support them while transitioning from OLSR to Babel. They will not contain these new Babel changes and, when one day OLSR is gone, they will no longer be able to connect to the network.

These are the models currently seen on the network that will drop off at some as yet undefined point in the future:

* AirGrid M2 XM  
* AirRouter         
* AirRouter HP    
* Bullet M5      
* Bullet M2 HP  
* NanoBridge M3  
* NanoBridge M5	  
* NanoStation Loco M2  
* NanoStation Loco M5  
* NanoStation Loco M9  
* NanoStation M2 XM  
* NanoStation M3 XM  
* NanoStation M5 XM

Note that while these devices are old and slow, the XW versions of them have enough RAM to not have to run the tiny build and thus will be able to stay connected after being upgraded to this production release.

**Migrate Legacy Tunnels**

Legacy tunnels are not able to carry the Babel protocol. Everyone has made good progress converting legacy tunnels to Wireguard tunnels since Wireguard was introduced, but we want to encourage those who have not made the switch yet to do so. Unfortunately we cannot do this automatically so once OLSR is removed, legacy tunnels will no longer work.

Documentation on setting up Wireguard tunnels can be found here: [https://docs.arednmesh.org/en/latest/arednGettingStarted/node\_admin.html\#add-tunnel](https://docs.arednmesh.org/en/latest/arednGettingStarted/node_admin.html#add-tunnel)

**PtP and PtMP RF modes**

This release adds PtP (point to point) and PtMP (point to multipoint) RF modes to complement our existing AdHoc mode. AREDN® has always done mesh networking by putting radios into AdHoc mode and this remains the default. These additional options allow for more optimal performance and better network management by making use of WiFi infrastructure mode.

We’ve seen notable throughput and latency improvements when using these modes, especially with 802.11ac devices. This  holds true even when mixing radios from different manufacturers. 

Documentation on these modes can be found here:  [https://docs.arednmesh.org/en/latest/arednGettingStarted/node\_admin.html\#mesh-ptp-settings](https://docs.arednmesh.org/en/latest/arednGettingStarted/node_admin.html#mesh-ptp-settings)

**Memory Limitations**

During the transition between OLSR and Babel, nodes will be running two sets of routing and service discovery daemons. This increases the memory footprint of AREDN®. On some nodes running extra services, especially those with active tunnels and hotspots, you may experience out-of-memory errors. Until OLSR is deprecated in future releases, we advise you to reduce this extra burden on these devices as much as possible. This is most likely to occur on the hAP AC Lite as they are a general workhorse for many and only have 64M of RAM.

**Known Issues**

* Basic mesh mode does not work with the OpenWRT One router. PtMP, PtP and Station modes work correctly.

**Other Enhancements**

Over and above those major additions, these enhancements have been added:

* Upgrade to OpenWRT 24.10.1  
* Improve speed of MIkrotik AC links.  
* Add message encouraging backups before upgrades  
* Made web server available on ipv6 link local address  
* Improved the sysupgrade process  
* Decreased reserved memory  
* Make the “yellow” message handling simpler and more flexible  
* Now save a little more memory on 64 MB nodes  
* Added more per link babel stats  
* Improved ping time measurements  
* Added a message encouraging backups before upgrades  
* We no longer allow new legacy tunnels  
* Now display the mac address for each radio  
* Added 1 decimal place to azimuth and elevation  
* Now provide 1 decimal point of significance to maximum distance.  
* Optional zram swap  
* Converted Link Quality Manager to Link Quality Monitor  
* Added an error message for unsupported ssh key upload  
* Improved supernode detection for when there isn't a supernode  
* Added HW Watchdog improvements  
* Tweaked WiFi AP params to improve connection stability  
* Enabled ed25519 ssh keys   
* Added a reminder to migrate legacy tunnels  
* LQM monitoring simplifications   
* When we fail to download firmware, ping host to see if it's reachable for better error reporting  
* Consolidated several different radio distance calculation routines  
* Removed Wireless Watchdog LQM  
* Now detect new radio modes   
* Added Babel mesh page navigation  
* Improved grouping on Babel mesh page  
* Alternate mesh page using Babel data  
* Split out tunnel counts in JSON file  
* Improved compactness of mesh data  
* Now support luasocket library  
* Added ucode debug library  
* Now identify supernodes using Babel when available

**New Device Support**

* Added support for OpenWRT One router  
* Add support for Vultr VM

**Fixes**

* Publish supernodes names specifically in ArednLink  
* Include Babel only links in link\_info sysinfo.json  
* Better compatibility with babel only neighbors  
* Restart Arednlink when we restart Babel  
* Suprenode prefix cleanup  
* Fixed missing .local.mesh on various Babel dns names  
* Fixed check-service array reuse bug  
* Fixed pasting into lat/lon fields  
* Supernode prefix cleanup  
* Now handle missing LQM info from older neighbors  
* Sysupgrade was failing to backup directories, only choosing files \- now fixed  
* Fixed how we read the active tx radio power  
* Fixed tunnel link-local (IPv6) addresses  
* Now we don't set country in wifi config as it sets flags we don't want set  
* Fixed arping link test  
* Now only run wireless monitor in adhoc mode  
* Fixed metrics error when bandwidth not set  
* Fixed identification of Ubiquiti AC radios when auto distancing  
* Fixed setting LAN addresses when DHCP is disabled   
* Fixed firmware download progress parsing  
* Fixed up the wifi address when missing  
* Fixed firmware upload typo  
* Now don't forward AAAA requests upstream  
* Now filter out AAAA dns responses  
* WiFi WAN mode now overrides any WAN port settings  
* Mode 44net setup more configurable  
* Now only do adhoc reset when actually in adhoc mod  
* Blocked the use of certain channels in PtxP modes (for now)  
* Added patch to work around pipe+lines EINTR LUA bug  
* Restricting valid wifi channels for wide bands  
* Refixed the LZ77 decompression for Mikrotik  
* Fixed occasional parse error when OLSR returns nothing  
* Removed dummy localap hostname  
* Fixed dialog close race condition  
* Lowered min\_free\_kbytes to 1M (from default of 16M  
* Avoid possible memory leak when retrieving babel host routes  
* Improved babel/lqm interaction when starting up ac nodes   
* Tiny builds do not support Babel. Made sure all the various extras handle this  
* Now hide unreachable services from AREDNlink like we do for OLSR  
* Fixed babel device count  
* Now handle missing IPs from tunnels and xlinks.  
* Disable wifi scan option for some mesh modes.   
* Switch to using reload script for AREDNlink updates  
* Improved selection of the radio band assigned to a radio  
* Don't support some wifi modes on tiny builds  
* Fixed layout of icons next to no-link services  
* Now update the mac allow every time LQM updates (it gets overwritten sometimes)  
* Now capture mac filters in support data  
* Fixed radio1 typo (had used radio0)  
* Removed code to disable mesh-to-wan when in NAT mode (why was this a thing?)  
* Improved bandwidth options for OpenWRT One  
* Added OpenWRT One to Ethernet port usage  
* Fixed identification of mesh rf   
* Reduced parallel requests on devices \< 64M (temp)  
* Rework default setup of radios when switching modes.   
* Now try link-local address for data fetch if other ip fails  
* Made sure we keep the supernode name when checking services

# 3.25.2.0

## Features

* New Mobile UI
* Backup and Restore node configurations
* Responsive design for desktop UI on smaller screens
* Improved logged-out experience to provide more information
* Improved WiFi Signal tool which shows SNR at both ends of link
* Support for ARDC’s 44-Net
* Upgraded to the latest OpenWRT release: 24.10

## Notes

* By default LAN devices are no longer permitted to access the Internet over the mesh. This can be re-enabled if required.
* The old UI is no longer available.
* We recommend the High Contrast theme when using the mobile UI outside.
* The new WiFi Signal tool requires both ends of a link be running the latest firmware.

## Enhancements

* Added more USB controller modules [\#1878](https://github.com/aredn/aredn/pull/1878)
* Added usbutils loadable package [\#1875](https://github.com/aredn/aredn/pull/1875)
* Improved firewalling of LAN [\#1862](https://github.com/aredn/aredn/pull/1862)
* Made further improvements to LAN to WAN firewalling. [\#1863](https://github.com/aredn/aredn/pull/1863)
* Enabled 44NET LAN configurations [\#1548](https://github.com/aredn/aredn/pull/1548)
* Enabled kmod-eeprom-at24 package [\#1529](https://github.com/aredn/aredn/pull/1529)
* Made watchdog improvements [\#1322](https://github.com/aredn/aredn/pull/1322)
* Report IP Address at the end of command line setup. [\#1861](https://github.com/aredn/aredn/pull/1861)
* Now allow local NTP server to run as a service for LAN devices [\#1865](https://github.com/aredn/aredn/pull/1865)
* Now allow ping and traceroute to auto select the best interface [\#1856](https://github.com/aredn/aredn/pull/1856)
* Animated the commit message like the scan message [\#1839](https://github.com/aredn/aredn/pull/1839)
* Added rpcapd loadable package to aid remote node monitoring [\#1838](https://github.com/aredn/aredn/pull/1838)
* Added disconnect reporting [\#1831](https://github.com/aredn/aredn/pull/1831)
* Throttle dnsmasq restarts when names change [\#1826](https://github.com/aredn/aredn/pull/1826)
* Improved messaging in various parts of the network setup [\#1817](https://github.com/aredn/aredn/pull/1817)
* Attempt to guess PC hardware and better support unknown hardware (for VMs). [\#1816](https://github.com/aredn/aredn/pull/1816)
* Include main IP address in HNA4 records [\#1814](https://github.com/aredn/aredn/pull/1814)
* Dnsmasq performance improvements. [\#1813](https://github.com/aredn/aredn/pull/1813)
* QEMU User Agent available as a module for x86 build [\#1798](https://github.com/aredn/aredn/pull/1798)
* Improved mesh device and service counts [\#1796](https://github.com/aredn/aredn/pull/1796)
* Moved the LAN DHCP enable/disable option into the LAN DHCP panel [\#1788](https://github.com/aredn/aredn/pull/1788)
* Improved tunnel "email" messaging [\#1773](https://github.com/aredn/aredn/pull/1773)
* Support forcing DHCP options without a specific tag [\#1769](https://github.com/aredn/aredn/pull/1769)
* Open a new tab for help and website menu links [\#1760](https://github.com/aredn/aredn/pull/1760)
* Improvements to the wifi watchdog [\#1757](https://github.com/aredn/aredn/pull/1757)
* Added a basic syslog tool [\#1744](https://github.com/aredn/aredn/pull/1744)
* Supernodes now support 44net by default [\#1753](https://github.com/aredn/aredn/pull/1753)
* Now provide 44net route override [\#1703](https://github.com/aredn/aredn/pull/1703)
* Added rapid-commit (dhcp) option [\#1733](https://github.com/aredn/aredn/pull/1733)
* Added command line tool to generate support data [\#1695](https://github.com/aredn/aredn/pull/1695)
* Added command line backup util [\#1729](https://github.com/aredn/aredn/pull/1729)
* Sped up commits [\#1721](https://github.com/aredn/aredn/pull/1721)
* Added DHCP option validation [\#1718](https://github.com/aredn/aredn/pull/1718)
* Now support DHCP options without values [\#1735](https://github.com/aredn/aredn/pull/1735)
* Gave high contrast theme wider dialogs (now we support that) [\#1716](https://github.com/aredn/aredn/pull/1716)
* Now support non-admin neighbor info in mobile view. [\#1714](https://github.com/aredn/aredn/pull/1714)
* Improved help for mobile wifi 	signal tool. [\#1693](https://github.com/aredn/aredn/pull/1693)
* Improved display of blocked neighbors [\#1709](https://github.com/aredn/aredn/pull/1709)
* Provide proxy and redirect for problematic services [\#1699](https://github.com/aredn/aredn/pull/1699)
* Now allow scanning of non-mesh and multiple wifi devices [\#1578](https://github.com/aredn/aredn/pull/1578)
* Made tunnel server name optional if you have no server tunnels [\#1688](https://github.com/aredn/aredn/pull/1688)
* Now support pasting lat,lon coordinates into either lat or lon map field [\#1687](https://github.com/aredn/aredn/pull/1687)
* Now support Y.X style radio heights [\#1673](https://github.com/aredn/aredn/pull/1673)
* Now filter the LAN name from node hosts [\#1669](https://github.com/aredn/aredn/pull/1669)
* Added pseudo services for Local Devices [\#1665](https://github.com/aredn/aredn/pull/1665)
* Now allow packages to be removed on low memory nodes. [\#1684](https://github.com/aredn/aredn/pull/1684)
* Improved detection and display of services and devices [\#1683](https://github.com/aredn/aredn/pull/1683)
* Improved which local devices and service we show when logged out or logged in. [\#1682](https://github.com/aredn/aredn/pull/1682)
* Provide UI for the wifi watchdog system. [\#1655](https://github.com/aredn/aredn/pull/1655)
* Improved tunnel messaging [\#1648](https://github.com/aredn/aredn/pull/1648)
* Added topology info to sysinfo.json [\#1637](https://github.com/aredn/aredn/pull/1637)
* Improved startup of LQM so we get some information early [\#1632](https://github.com/aredn/aredn/pull/1632)
* Support wider channels (experimental) [\#1631](https://github.com/aredn/aredn/pull/1631) [\#1635](https://github.com/aredn/aredn/pull/1635)
* Split the Wifi Signal gauge to 	show the local and remote signal information [\#1602](https://github.com/aredn/aredn/pull/1602) [\#1628](https://github.com/aredn/aredn/pull/1628)
* Improved detection of disconnected nodes [\#1617](https://github.com/aredn/aredn/pull/1617)
* Periodically sync time if continuous NTPD is unsynchronized [\#1611](https://github.com/aredn/aredn/pull/1611)
* Now include cookies when testing services. [\#1600](https://github.com/aredn/aredn/pull/1600)
* Improved antenna settings messaging [\#1605](https://github.com/aredn/aredn/pull/1605)
* Added VHT support (experimental) [\#1630](https://github.com/aredn/aredn/pull/1630)
* Decimate the neighbor graph data so we can show more history [\#1598](https://github.com/aredn/aredn/pull/1598)
* Added capability to backup and restore node configurations [\#1597](https://github.com/aredn/aredn/pull/1597)
* Added secondary NTP server option [\#1583](https://github.com/aredn/aredn/pull/1583)

## New Device Support

* TP-Link CPE710v2 [\#1823](https://github.com/aredn/aredn/pull/1823)
* Mikrotik NetMetal 5
* Tupavco antenna [\#1646](https://github.com/aredn/aredn/pull/1646)
* Ubiquiti Litebeam M5

## Fixes

* Fix tx/rx bitrate reporting which was 1/2 what it should be. [\#1882](https://github.com/aredn/aredn/pull/1882)
* Improve api performance when reading radio info. [\#1881](https://github.com/aredn/aredn/pull/1881)
* Added fix to br-nomesh which can be created in a partially working state [\#1844](https://github.com/aredn/aredn/pull/1844)
* We no longer allow access to port 9090 from the mesh. (It crashes OLSRD) [\#1879](https://github.com/aredn/aredn/pull/1879)
* Added lockdown and monitor for OLSR [\#1852](https://github.com/aredn/aredn/pull/1852)
* Reapplied older patch for Rocket 5AC Lite [\#1872](https://github.com/aredn/aredn/pull/1872)
* Improved setup migrations [\#1834](https://github.com/aredn/aredn/pull/1834)
* Restart LQM when tunnel configuration changes. [\#1832](https://github.com/aredn/aredn/pull/1832)
* Don't display supernode route count 	(supernodes don't calculate this) [\#1825](https://github.com/aredn/aredn/pull/1825)
* Increased dnsmasq cache sizes for supernodes to avoid memory corruption [\#1811](https://github.com/aredn/aredn/pull/1811)
* Bumped restart timeouts so dnsmasq will respawn if it crashes. [\#1810](https://github.com/aredn/aredn/pull/1810)
* Fixed corner case when setting up node's initial Addresses [\#1804](https://github.com/aredn/aredn/pull/1804)
* Fixed display problem when arp contains bad entries [\#1802](https://github.com/aredn/aredn/pull/1802)
* Fixed resource caching in browser memory [\#1795](https://github.com/aredn/aredn/pull/1795)
* Don't refocus the mesh page when we refresh so page doesn't jump to the top [\#1794](https://github.com/aredn/aredn/pull/1794)
* Fixed layout of LAN type so it looks the same on all browsers [\#1866](https://github.com/aredn/aredn/pull/1866)
* Made sure we hide any overflowed nav controls [\#1780](https://github.com/aredn/aredn/pull/1780)
* Fixed port forward layout [\#1775](https://github.com/aredn/aredn/pull/1775)
* Now force wifi lan/wan password to be at least 8 characters [\#1767](https://github.com/aredn/aredn/pull/1767)
* Fixed the source Addresses for pings and traces [\#1765](https://github.com/aredn/aredn/pull/1765)
* Fixed port forward wrapping [\#1758](https://github.com/aredn/aredn/pull/1758)
* Fixed an unresponsiveness when network changes [\#1740](https://github.com/aredn/aredn/pull/1740)
* Made 3 column layout responsive if browser is narrow [\#1741](https://github.com/aredn/aredn/pull/1741)
* Made more fixes and improvements to DHCP option validation [\#1736](https://github.com/aredn/aredn/pull/1736)
* Fixed creating new first reservation 	[\#1734](https://github.com/aredn/aredn/pull/1734)
* Fixed DHCP option input field number styling [\#1731](https://github.com/aredn/aredn/pull/1731)
* Made fixes and tweaks for DHCP option in-browser validation [\#1730](https://github.com/aredn/aredn/pull/1730)
* Fixed the assumption that the DHCP range always starts at an offset of 2\. [\#1726](https://github.com/aredn/aredn/pull/1726)
* Added localnode back into port forwarding UI [\#1706](https://github.com/aredn/aredn/pull/1706)
* Made various bug fixes for alt networks and larger dhcp ranges [\#1652](https://github.com/aredn/aredn/pull/1652)
* Made fixes for blank variables breaking upgrades [\#1654](https://github.com/aredn/aredn/pull/1654)
* Fixed DMZ DHCP values [\#1664](https://github.com/aredn/aredn/pull/1664)
* Fixed migration of services on nodes without any services [\#1660](https://github.com/aredn/aredn/pull/1660)
* Now allow ":" in service names [\#1638](https://github.com/aredn/aredn/pull/1638)
* Fixed firewall restart when lan-to-wan changed [\#1606](https://github.com/aredn/aredn/pull/1606)
* Now redirect localnode to actual hostname (better logged-in behavior) [\#1599](https://github.com/aredn/aredn/pull/1599)
* Only show TODOs to admin [\#1595](https://github.com/aredn/aredn/pull/1595)
* Mark devices supported in previous releases, but not in the current one. [\#1748](https://github.com/aredn/aredn/pull/1748)
* Refine PUT/POST locking. [\#1742](https://github.com/aredn/aredn/pull/1742)
* Tweak node detection keepalive [\#1713](https://github.com/aredn/aredn/pull/1713)
* Refine htmx activation mechanism 	[\#1712](https://github.com/aredn/aredn/pull/1712)
* Make sure we don't lose the compat\_version [\#1697](https://github.com/aredn/aredn/pull/1697)
* Supported Devices List Edits (UBNT 5AC)-Issue \#1674 [\#1675](https://github.com/aredn/aredn/pull/1675)
* Remove setting old dmz value [\#1657](https://github.com/aredn/aredn/pull/1657)
* Mark bandwidths invalid on various devices (rather than marking what is valid) [\#1639](https://github.com/aredn/aredn/pull/1639)
* Make sure to silence the wifi signal on the way out [\#1623](https://github.com/aredn/aredn/pull/1623)
* Work around HTMX bug where downloading files doesn't stop the logo spinning [\#1622](https://github.com/aredn/aredn/pull/1622)
* Remove special casing for /a/authenticate page [\#1619](https://github.com/aredn/aredn/pull/1619)
* Fix missing validation for single hx-put input fields [\#1618](https://github.com/aredn/aredn/pull/1618)
* Block PUT, POST, DELETE unless logged in or firstboot. [\#1582](https://github.com/aredn/aredn/pull/1582)
* Added user agents (containing firmware version info) to package and firmware updates [\#1593](https://github.com/aredn/aredn/pull/1593)

# 3.24.10.0

The biggest change in this release if you haven't been keeping tabs on AREDN, is the "new UI". The old UI, written in LUA not only looked old, it was hampering the implementation of new features.  Now written in Javascript, among other things it's more economical on bandwidth used to display the user interface.  It's also much easier to add new features. The new UI has taken 6 months and the work of many, many people. We’d like to thank everyone involved with developing, documenting, and especially debugging this; we really appreciate our community.

Because it's new, navigating around it may initially be a challenge. Steve, AB7PA, keeper of the AREDN docs, has done a stellar job in documenting the new UI. It's highly recommended you at least skim them, here http://docs.arednmesh.org/en/latest/ Within the new UI you will also find a Help button for every dialog. Please press it and read the inline help at least once. Finally, we recorded a walkthrough of the new UI which you can find here https://www.youtube.com/watch?v=KG_2ploIYzg (note that there have been a few minor changes since we did this).

After upgrading, you may be returned to the old UI or you might see the new UI. In either case you will see a green button in the upper-right-hand corner of your browser window which lets you toggle between them. In the new UI you will initially be in Guest mode. To log into Admin mode, click on the little guy in the upper-right-hand corner, click on Login and enter the node's password (no need for a user name).

## Enhancements

* New UI. All the enhancements below are in the new UI only. The old UI remains unchanged.
* New custom UI when first installing nodes.
* Ability to remove unused tunnels
* Added a weight to tunnels, now on a per-tunnel basis (the "weight" artificially degrades the tunnel's ETX; if an RF route exists and its ETX value is better, it will be preferred)
* Themes support: default, high contrast, color-blind, dark, and light.
* Portable themes let you set a theme on your localnode and see it on every other node. So if you’re color blind for example, you can set that once and see it everywhere.
* If a node can get to http://downloads.aredenmesh.org it will indicate if a code update is available. Nightly nodes will be notified of nightly updates, while release nodes will be notified of release updates.
* Added update progress indicator when downloading or uploading firmware.
* Added ability to switch between 12 hour and 24 hour displays
* DHCP aliases are now rewritten when DHCP range changes
* Now show Metric units if your locale isn't "en-us" or “en-gb”
* Added the option to prevent LQM from blocking poorly performing links. This allows you to keep LQM active and let it manage link performance, without it shutting down crucial connections.
* Added topic-sensitive Help in every configuration dialog.
* Added always-running NTPD option
* Added GPS support (see https://github.com/kn6plv/WhereAndWhen for how to install a GPS receiver) which is shared by all DTD connected nodes.

## New Device Support

* Ubiquiti Nanobeam 5AC WA
* Support for newer Mikrotik devices with can only use the Mikrotik v7 bootloader

## Fixes and Improvements

* Fixed Ubiquiti AC devices failing wifi scan if on 10MHz
* Fixed time drifting problem on Basebox 5, QRT 5, non-AC mANT 19S
* User firewall rules are now preserved across upgrades
* Fix supernode locator. Now correctly finds the closest one.

## Notes

* The way the tunnel addresses are allocated has changed in the new UI. In some unlikely cases you may need to remove a tunnel and re-add it.
* While we provide both UIs in this release, trying to use both interchangeably can cause problems. Once you start using the new UI, please don’t go back and use the old one.
* There remain problems with the TP-Link CPE710.
* GL.iNet GL-B1300 does not support negative channels on the 2.4 GHz band.
* The Litebeam M5 is no longer supported.

# 3.24.6.0

## Enhancements

* MTR support via installable package (mtr-nojson).
* NAT mode: Allow NAT traffic to LAN from all interfaces (WAN, RF, DTD, TUN, WG and XLink).
* Improve iPerf3 service to provide data line by line rather than at the end.
* Use closest supernode rather than first discovered supernode.
* LQM+OLSRD improvements where weak connections are detected.
* Detect "leaf" nodes and prevent them being blocked.

## New Device Support

* Antenna: Mikrotik 30 dBi 5deg Dish
* Antenna: airMAX 2.4 GHz, 24 dBi 6.6deg RocketDish
* Antenna: airMAX 3 GHz, 26 dBi 7deg RocketDish
* Antenna: airMAX 3 GHz, 18 dBi, 120deg Sector
* Antenna: airMAX 3 GHz, 12 dBi Omni
* Antenna: airMAX 5 GHz, 30 dBi 5.8deg RocketDish Light Weight
* Antenna: Mikrotik 15 dBi 120deg Sector
* Antenna: Mikrotik 19 dBi 120deg Sector
* Antenna: Mikrotik 30 dBi 5deg Dish (PA)

## Notes

* There remain problems with the TP-Link CPE710.
* GL.iNet GL-B1300 does not support negative channels on the 2.4 GHz band.

## Fixes and Improvements

* Add service validation state to support data.
* Name xlink configs.
* Fix missing file error when retrieving messages.
* Simplify olsrd watchdog.
* Fix bug requiring reboot when updating tunnels.
* Ignore badly formatted service definitions.
* Update AREDN® registration marks.
* Count Wireguard tunnels in sysinfo.json reporting.
* Fix NAT Firewall for tunnels and xlinks. Moved to stanard OpenWRT firewall configuration rather than custom rules.
* Force DHCP server active even when other servers detected (restore OpenWRT 22.03 behaviour).
* Fix check-services bug when all services fail.
* Fix manager.lua busy wait bug.
* Fix hostname alias pattern to allow dns delegation.
* Use more reliable system ip-to-hostname lookup rather than hand-rolled version.
* Fix status page infor for 900MHz devices.
* Move all logging into syslog so it can be logged remotely.
* Change web, telnet and ssh WAN settings without reboot.

# 3.24.4.0

## Enhancements

* Wireguard tunnels
* Configurable DHCP options
* Antenna information
* Watchdog support
* Remote logging
* OpenWRT 23.05.3

## New Device Support

* Mikrotik mANTbox 2 12s
* GL.iNet E750 
* GL.iNet GL-B1300
* GL.iNet GL-MT1300
* GL.iNet AR300M NAND
* Ubiquiti Litebeam 5AC LR
* Ubiquiti Nanobeam 2AC
* Unraid
* VMWare ESXi

## Notes

* This release is incompatible with MeshChat 2.9 or earlier.
* GL.iNet GL-B1300 does not support negative channels on the 2.4 GHz band.

## Fixes and Improvements

* Updated to latest OpenWRT 23.05.3
* Fixed wifi scan for Ubiquiti AC devices
* Now ignore tracker entries without IP addresses 
* Limit buffer size of IPerf3 test to 16K
* Improved IPerf3 api reliability
* New supernodes will no longer have access to legacy tunnels
  * Legacy tunnels will be removed from supernodes in the next prod release
  * NOTE: in the distant future, legacy tunnels will be completely removed.  Migrate to Wireguard tunnels now and avoid the rush :-)  They’re way better anyway.
* Collapsed QEMU and VMWARE VM hardware into two basic types
* Validated network override configs
* Now hide long time idle neighbors
* Fixed PowerBeam 5AC 400 name
* Labeled Wireguard tunnels in LQM
* Added support for dynamic number of Ethernet ports on VMs
* Don't run iwinfo if we have no wifi
* Improved hidden node reporting & fixed column alignments
* Improved link labels (add RF and Wireguard)
* Improved link monitoring
* Configuration updates without reboots
* Unified Neighbors and Mesh pages
* Firmware downloads:
  * Added retry for failed firmware version downloads 
  * Improved the messaging when failing to retrieve firmware versions
* Fixed tunnel net display truncation on some browsers
* Made sure the node names we use for tunnels are always uppercase
* Switched Nanobeam 2AC to DD-WRT firmware (doesn’t function on 10MHz otherwise)
* Fix display of NTP update when it changes
* Add rev DNS lookup for supernode tunnels 
* Make sure switching wifi modes forces a reboot.
* Fixed wan client/no encryption mode
* Fixed xlink monitoring by LQM
* Removed fixed tunnel limits
* Improve VLAN selection in advanced networking
* Fixed all x86 mac addresses
* For x86 devices, make all the bridge mac addresses unique. Gives more flexibility when virtualized.
* Added extra protection for bad OLSR info
* Fixed bug in route truncation in low memory situations
* Now refresh browser cursor on each LQM iteration
* Ports Page:
    * Added Advanced DHCP Options selector on Port Forwarding, DHCP, and Services page
* Front Page: 
    * Now show antenna information on the front page
    * Internal antenna info is automatically shown
    * External antenna info may be added on the Basic Setup page
    * Added frequency range on front page to help detection of overlapping channels
* Basic Status page:
    * Added support for azimuth, elevation, height above ground and external antenna type
    * Note – if the node has azimuth information set, the bearing of its antenna will be displayed on the mesh map by rotation of the node’s pin on the map ( https://arednmap.xojs.org ).
* Mesh display improvements:
  * Added xlink display to remote nodes
  * Fixed LQ display of weighted local links
  * Fixed NLQ display of weighted links (using the LQ weight ... and assume its symmetrical)
  * Now sort the remote node list by ETX, then alphabetically
  * Fixed clearing the mesh search field
  * Another attempt to deal with occasional missing remote hosts
* Added watchdog support. The watchdog monitors three things:
  * A set of important system daemons. 
  * A set of pingable ip addresses. 
  * A time the node should reboot everyday. 
  * Countdown timers for reboots and firmware updates.
* Reboot pages will now refresh once the node is ready rather than after a fixed timeout.
* Increased wifi retries for noisy links
* Auto mesh page updates no longer persist
* Auto scan page updates no longer persist
* Eliminate duplicate past neighbors
* Support default /metrics path for Prometheus
* Fix various color problems on alternate display styles
* Add green on black style
* Half olsrd maintenance traffic rate
* Fix clashing IP address on devices with the same mac address ethernet and wifi hardware
* Fix Bad Gateway when rebooting from tunnel pages
* Add CIDR network to Xlinks
* Provide better xlink information in sysinfo.json
* Include tunnel information (redacted) in support data dumps
* Fix badly escaped character in tunnel gmail emails
* Improve speed and relevance of search on mesh page

# 3.23.12.0

## Enhancements

* Added Supernode support.

  "Supernodes" are specifically configured AREDN® nodes in various locations which support a 
"mesh of meshes". With this release your localnode will automatically detect a nearby 
supernode, and will show a new button on the Mesh Status page, labeled "Cloud Mesh". 
Clicking on that button will take you to the Mesh Status page of that supernode and show you 
all the nodes and services on the Cloud Mesh. You can navigate to any of them as though they
were on your local mesh.

  The URL for the supernode map is currently https://arednmap.xojs.org/  Clicking on any of the 
nodes in the upper-right-hand corner of the map will filter all other nodes out, showing only the 
types selected.

* Remember and reinstall packages after firmware upgrade (AFTER this version is installed)
* Simplified search tool
* Added LZ77 decompression for Mikrotik firmware, which is now using a different compression method
* Cron
  * Now run cron.boot tasks earlier
  * Changed pollrate default to one hour
  * Added installable cron package for people who need more functionality
* Improved dual radio configuration support in hAPs
* Added support for wildcard DNS subdomains
* Now using frequency list for scan.  Some hardware didn’t scan all the frequencies we want by default. (Not a fix for the scan issue seen on some AC devices.)
* Set tunnel weight to 1 and provided UI to change it. With this change, if there are both RF and tunnel links to a destination, the tunnel value can be set high (relatively poor).  In that way traffic will only flow over the tunnel if the RF link goes down.  This provides an effective method for implementing backup links.
* Bumped the allowed Ubiquiti version numbers to support AREDN® installation on newer LiteBeam 5ACs.  (Probably all new Ubiquiti devices but currently only tested on Litebeams).
* Xlink broadcast - Allow xlinks to broadcast OLSR traffic as well as targeting specific IPs.

## New device support

None in this release

## Bug fixes

* Now detect if we support firstboot mode (x86 VMs don't support it, so don't show the button in that case)
* Fixed dnsmasq directives 
* Correctly set wifi wan mode when depending on the mesh wifi setting.
* Corrected a bug where it would mess up the wan wifi when switching the band of the mesh wifi
* Made LQM neighbor improvements (fixed occasional exclusion of specific DtD neighbors)

## Known problems

* Ubiquiti 802.11ac devices - missing wifi scan and waterfall info

# 3.23.8.0

There have been over 70 nightly releases of the AREDN® codebase since the last production release in April of 2023. Here are the highlights of the latest production release:	 	

## Enhancements

* Added Prometheus Metrics (meant for use with monitoring apps like Grafana)
* SSH, TELNET and HTTP access to a node via the WAN port can now be disabled from the advanced configuration page.
* Improved handling of unsupported hardware.
* Use wifi assoc list when looking for unresponsive nodes
* Allow MTU on wifi interface to be modified
* Minor wifi monitor improvements for better metrics reporting
* Merge all the station monitoring and mitigation into a single service
* Support xlinks on x86
* Remove subnet restrictions for xlinks
* Support switching mesh radio on multi-radio devices
* UI improvements from AB7PA
* Upgrade to OpenWRT 22.03.5 
* Added Advanced Networking tab
* Feedback when pressing upload/download buttons
* Virtualized X86 support
* Restructure, modularize and tidy up the navigation buttons and menus
* Remove hardwired frequency tables and use information from the hardware instead
* Note devices which support the danger-upgrade process
* Allow the “&” character in service paths
* Added support for group alert messages

## Known Issues

* Wifi scanning on Ubiquiti AC devices does not return all found devices, only ones already associated with the node.

## New Devices Added

* New LiteBeam AC Gen2 variant
* Mikrotik LDF 5AC 
* Mikrotik LDF2
* PowerBeam 5ac-620 support

## Bug Fixes

* Fix x86 upgrades (naming is a little odd)
* Fix Mikrotik first install
* Re-enable AREDN’s reset button behavior (was being overridden by OpenWrt’s)
* Revert PowerBeam 5AC 400 name change which caused upgrade problems
* Remove another coverage test which causes problems
* Fix MTU failure which broke node setup
* Avoid error if mac disappears across a radio reset
* Monitor bug fixes
* Fix bug when editing xlinks on single port devices
* Enhance ‘has_wifi’ detection
* Handle non-wifi devices passed to maxpower/pwroffset functions 
* Fix LUA converting empty port object to empty array. 
* Alternate ath9k and ath10k radio reset for deaf nodes
* Fix API nil pointer when mac lookup fails
* Disable WAN access to node by default
* Fix disabled mesh on multi-wifi devices
* Split rocket-m[52]-xw into different builds
* Enable Rocket M XW (accidentally disabled when splitting out the M2 version)
* Fix wifi setup for multi-radio devices 05/08/2023
* Add missing radios.json for Powerbeam 5AC 400 05/07/2023 
* Remove old PBE 100mb fix and /etc/rc.local where it was included
* Fix channel display for 5GHz nodes
* Tidy up the formatting and fix column widths
* Fix syntax error in patch that broke network on many ath79 devices
* Fix ar300m16 wan configuration 04/25/2023
* Fix frequency range reporting and display for 900MHz & 3GHz devices
* Tolerate missing frequency list
* Fix missing POE for nanostation-m
* Remove ar300m nand and nor builds which are causing confusion
* Fix local message refresh 

# 3.23.4.0

There have been over 140 nightly releases of the AREDN® codebase since the last production release in December 2022. Here are the highlights:

## Major Enhancements

* Support for the ‘AC’ class of radios [2]
* Improved service validation
* Improved WiFi scanning
* Better error feedback for future upgrades
* Hidden and Exposed node handling [3]
* Enhance AP and WiFi Client channel selection
* Support for easier “nightly build” testing
* Upgraded to OpenWRT 22.03.3; the latest release of OpenWRT with many security and bug fixes.
* Upgraded to Linux kernel 5.10.161

**IMPORTANT NOTE!** 

Because of changes in the way OpenWRT names devices, this upgrade is not simple to revert without reinstalling your node as if you just took it out of the box.

## New Devices

* Ubiquiti [1]
    * LiteAP 5 AC
    * LiteBeam AC5 Gen2
    * NanoBeam AC 5 (WA)
    * NanoBeam AC 5 (XC)
    * NanoBeam AC 5 Gen 2 (WA)
    * NanoBeam AC 5 Gen 2 (XC)
    * NanoStation AC 5
    * PowerBeam AC 5 Gen2
    * PowerBeam AC 5 400
    * PowerBeam AC 5 500
    * Rocket 5 AC Lite
* Mikrotik
    * hAP ac2
    * hAP ac3
    * SXTsq 5 ac
    * LHG 5 ac
    * LHG XL 5 ac
    * LDF 5
    * mANTBox 15s
    * mANTBox 19s
* TPLink
    * CPE710 v1.0
* GL.iNet
    * Shadow (128MB NAND)
    * Slate
    * Mudi

For a full list of supported products, see the list [here](http://downloads.arednmesh.org/snapshots/SUPPORTED_DEVICES.md).

**Notes:**

1. **Important** - the initial factory installation instructions for Ubiquiti 802.11 ac products are new.  They can be found in the AREDN® Online Documentation [here](http://docs.arednmesh.org/en/latest/arednGettingStarted/installing_firmware.html#ubiquiti-802-11ac-first-install-process).

2. The 802.11ac products offer noticeable advantages over the legacy 802.11n devices.  If you’re contemplating a new deployment or just looking for better performance, consider an 802.11ac device.  Here’s [a list of recommended devices](https://www.arednmesh.org/content/device-migration-suggestions) for migrations.

3. Over and above neighbor status states of pending, active and idle, new states of hidden and exposed have been added. Because the nodes talk amongst themselves, your node knows which of its neighbor nodes are nearby but hidden from it. This can be useful for network management. Exposed nodes are nodes that a node can see, but will block it from transmitting to other neighbors when they are transmitting. It's a bit complex - see the 'exposed node problem' in Wikipedia for more detail The AREDN® team hopes to use these parameters in the future to reduce channel congestion.

## Full Change List

* RF performance improvements
    * Now automatically enable RTS (Ready To Send) when hidden nodes detected
    * Fixed IBSS (Independent Basic Service Set) problem on 2.4GHz
    * Enabled negative channels for 2.4 GHz 802.11ac devices
    * Fixed negative channels not beaconing.
    * Fixed power offsets on various devices
    * Fixed fccid beacon
    * Fixed -ac coverage calculation in driver.
    * Resolve unresponsive node problems with Mikrotik AC devices
    * Now ignore non-routable when calculating hidden nodes
* Network performance improvements
    * Added a maximum timeout for service checks
    * Provided a timeout on the iperf3 client
    * iperf3: Improve error reporting when server is busy/disabled
    * Set up to refresh LQM’s hostnames periodically
    * Made the default country HX (HAM)Now handle missing IP address and create more general RF/DTD identification
    * Validate state of services over a period of time before disabling advertisements
    * Force dnsmasq to update itself if no network changes for > 60 secs
    * Fixed idle tunnel quality check
    * Fixed WAN VLAN detection on hAP
    * Fixed the netmask on the br-nomesh device (for when RF mesh is disabled)
    * A node with a single RF link can’t have any exposed nodes - corrected
    * Filtered out non-routable ARP entries which confuse LQM
    * Don't let services use hostnames which are not propagated.
    * Block DHCP server traffic from ever going to the WAN interface
    * Reworked the DTD blocking detection
    * Fix occasional LQM nil error
    * Eliminate false network rejoins using LQM information
    * Force badly associated stations to reassociate.
* Node management improvements
    * Improved the quality of the scan output
    * Improved idle tunnel quality measurement
    * Provided better error feedback when upgrades fail
    * Tagged devices which must be reinstalled. (The NAND layout for a few Mikrotik devices has changed sufficiently that they cannot be easily upgraded and must be reinstalled from scratch.)
    * Now gather statistics about RF links
    * Established a more consistent way to provide interface mac address in overrides
    * Support forced upgrades
    * Move the unconfigured setup earlier
    * Handle system upgrade files of type “nand-sysupgrade”
    * Remove WAN Wifi Client key lower limit
    * Improve AP band selection
    * Add extended channels to LAN AP list
    * Fixed PowerBridge M upgrade
    * Fixed AirRouter port identification
    * Made sure we look for packages with the correct architecture
    * Fixed AR150 port settings
    * Fixed Mikrotik boot loader to avoid boot lockup problem
    * Improved firmware failure error recovery
    * Stop RETURN from refreshing the mesh page
    * Fixed support for Mikrotik LHGG-5acd-xl
    * Fixed upgrade compatibility for nanobeam m5 19
    * Fixed AP mode selection when turning mesh back on.
    * More fixes for AP mode
    * Fixed firewall rule checking for existing drop rules
    * Fixed monitors not detecting non-mesh mode
    * Created new network configuration code
* Miscellaneous
    * Merged openwrt release 22.03.3
    * Updated firmware selector on web page
    * Made sure we never pass ‘nil’ to the json parser
    * Fixed xlink firewall rule inserted incorrectly
    * Removed a firmware blocker we no longer need
    * Added a note about the USB150 & AR150 devices
    * Added "hidden" and "exposed" node statuses to help file
    * Re-enabled the  kmod-rtc-ds1307 package
    * Some initramfs cleanup
    * Generalized node-setup variable expansion
    * Removed firewall counters except for specific ports
    * Now use luci’s urldecode_params to handle query strings
    * Added “tiny build” notes
    * Set PowerBeam-M2-400 to stable status
    * Fixed service alignments on web page
    * Add SKUs to Supported Devices doc
    * Cleaned up Supported Devices doc
    * Split the various Mikrotik radios into their individual variants
    * Clarified the Mikrotik LHG 2nd firmware versions
    * Validate Bullet M5 build
    * More upgrade compatibility
    * Ath9k driver - no error accounting - added
    * Fixed the bandwidth reporting for ath10k devices

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

The AREDN® development team has shifted into high gear with this third release of 2022!  This production release adds the many fixes and enhancements made since 3.22.6.0

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

AREDN® production release 3.22.6.0 is now available.  This is the release you've been looking for :-)

Since the last production release, there have been 136 separate ‘pull requests’ in the AREDN® github repository.   Those requests pulled these significant improvements and new features into the AREDN® software:
1. The conversion from Perl programming to Lua is complete - the result is a significantly smaller, somewhat faster, code base.

2. Due to the recovered space in the image, tunnels are now always installed, so nothing needs to be done with them during future upgrades.

3. After this upgrade, future upgrades should be much more reliable, especially on low memory devices.

4. Tunnels will be prevented from accidentally connecting over the mesh.

    Tunnels normally connect via the WAN interface, that being the point of the things. However, if the WAN interface on a node goes down for some reason (the tunnel server/client Internet fails) the node will select a new way to talk to the Internet by first routing over the Mesh. When this happens, tunnels could end up being routed partially over the mesh, which is bad because tunnels are also part of the mesh. So, we now prevent this by default by adding a firewall rule.


5. You can now adjust the poll rate for alerts. AREDN® alerts and local alerts (those yellow banner things you see sometimes) were polled twice a day. This is now configurable.

6. There is now a 60-second timeout when tunnel connections are interrupted. 

    Node tunnels run over TCP/IP so they guarantee that what is sent is what will be received. This is all fine when things are running reliably, but if a connected tunnel fails for a bit, but then recovers, this guarantee means very old, pending traffic will still be delivered. In AREDN’s case, this traffic is not useful to the user, and for OLSR it is positively dangerous to deliver ancient routing information. This is all low level protocol stuff and there will be no visible effects to users.


7. Nodes which are only connected via the WAN port and tunnels (no Wifi, no LAN) can cause some configuration problems because AREDN® really wants either the LAN port to be connected or the WiFI to be enabled. We made some changes, so this is no longer a requirement. Thanks to K1KY, who has some unusual setups, for finding this.

8. Automatic NTP sync - we now locate an NTP server (either the one configured or by searching the mesh for a local one) and sync the time daily.

9. Added the ability to change the default VLAN for the WAN port. Currently not available on devices which contain network switches.

10. Included iperf3 by default, as well as a simple web UI. Its use is described here in the AREDN® online docs.

11. Updated the Advanced Configuration page; sorted items on the page into categories.

12. Added the capability of loading firmware updates "locally" after copying them to the node via SCP.  This is useful if you’re trying to update a distant node over marginal links.   Information on how to use it is in the AREDN® online docs, here.

13. Nodes will now drop nodenames and services that haven't been included in a broadcast for approximately 30 minutes.

14. The hardware brand and model have been added to the main page.

15. Messages banner will only be displayed on the Status & Mesh pages, keeping the setup & admin pages uncluttered.

16. Channels -3 and -4 have been added to 2 GHz, for use in those countries where it’s legal.

17. Added link quality management (LQM). It’s designed to make the AREDN® network more stable and improve the available bandwidth.    

    When enabled LQM accomplishes this in two ways:
First, it drops links to neighbors which won't work well. Links are dropped that don't have good SNR, are too far away, or have low quality (forcing retransmissions).
Second, it uses the distance to the remaining links to optimize the radio which improves the bandwidth. This mechanism replaces the older ‘auto-distance’ system which was often confused by distant nodes with which it could barely communicate.


Many LQM parameters are capable of being modified to allow for local network circumstances.  There’s documentation on LQM in both the node help file and in the AREDN® on-line docs.

**NOTE 1:** LQM is turned off by default, unless it was previously enabled in a nightly build.

**NOTE 2:** Latitude and longitude need to be configured in order for LQM to work properly.
 
**IMPORTANT NOTE:** If you’re running MeshChat and/or iPerfSpeed, after this upgrade you’ll need to install compatible versions of them (but note that with the built-in throughput test you may no longer need iPerfSpeed).  URLs for those versions:

iperfSpeed: https://github.com/kn6plv/iperfspeed/raw/master/iperfspeed_0.6-lua_all.ipk

MeshChat: https://github.com/kn6plv/meshchat/raw/master/meshchat_2.0_all.ipk

# 3.22.1.0

This release includes many significant improvements in the underlying OpenWRT code and stability/scalability fixes to the OLSR mesh routing protocol.
 
## List of Changes:
​
1. The AREDN®  simplified firmware filename standard has been changed to the default OpenWRT convention to leverage data files created at build time for future automation of firmware selection.

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
* Add advanced config option to purge AREDN® Alert msgs #76 (dman776)
* Update alert banner background color #72 (ab7pa)
* Reset download paths upon upgrade to default #69 (dman776)
* Upgrade to openwrt 19.07.7 #68 (ae6xe)
* Add new Mikrotik model string for SXTsq5nD #62 (ae6xe)

# 3.20.3.1

The AREDN® team is pleased to announce the general availability of the latest stable release of AREDN® firmware. We now fully support 70+ devices from four manufacturers. This diversity of supported equipment enables hams to choose the right gear for a given situation and budget.

Here is a summary of the significant changes since 3.20.3.0 was release:

* Migrate all remaining TP-Link models to ath79 target
* Fix CPE510 v3 image not installing
* Fix Ethernet port to fully conform with AREDN® expected usage on NanoStation M5 XW
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

The AREDN® team is pleased to announce the general availability of the latest stable release of AREDN® firmware. We now fully support 70+ devices from four manufacturers. This diversity of supported equipment enables hams to choose the right gear for a given situation and budget.

AREDN® firmware is now based on the most recent stable version of OpenWRT19.07.2 which was released in March 2020. This improvement is significant in that it enables AREDN® firmware to benefit from the many bug fixes, security improvements and feature enhancements provided by OpenWRT developers from around the world.

The latest AREDN® firmware contains features inherited from the newest OpenWRT upstream release (19.07.2). One important change is the inclusion of a new target (architecture) for the firmware, labelled “ath79”, which is the successor to the existing “ar71xx” targets. OpenWRT explains that their main goal for this target is to bring the code into a form that will allow all devices to run a standard unpatched Linux kernel. This will greatly reduce the amount of customization required and will streamline the firmware development process. As not all supported devices have been migrated to the new “ath79” target, AREDN® continues to build firmware for both targets.  You may notice that the AREDN® download page has firmware for these two targets, and you should select the latest image based on the type of hardware (and the recommended target) on which it is to be installed. 

## Changes to the Supported Platform Matrix

Several devices are now shaded in light green to indicate that they are no longer recommended for AREDN® firmware, primarily due to their low computing resources (memory/storage).

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

* Added /etc/board.json to AREDN® support data download #483 (ae6xe)

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

OLSR is the capability in AREDN® that exchanges IP Addresses, Hostnames, and figures how to route packets across the mesh network.   There continues to be an intermittent defect when OLSR starts as a device is powering up. OLSR fails to propagate or may miss receiving some hostname information.  A one-time restart of OLSR will resolve the situation. This option can be found in Advanced Configuration settings--it doesn’t save a setting per se, rather restarts OLSR without rebooting the device.  

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

2) Do not count on being able to sysupgrade to return back to older AREDN® images, when upgrading to ‘ath79’ target images.    It might work, it might not based on if model names were cleaned up and changed moving to ath79. The older images may not be recognized on the newer target images.  Do a tftp process instead.

3) To know what image to use, pay close attention to the table located here (scroll down):  https://github.com/aredn/aredn_ar71xx .
