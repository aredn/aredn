# Supported Devices

**Stability**
* *untested* - this image has not been tested on hardware. It may or may not work.
* *stable* - this image has been tested on hardware. There may still be bugs.

**Status**
* *released* - this image is in a production release of the AREDN® firmware.
* *nightly* - this device is newly supported in the nightly builds (since the last production release).
* *sunset* - this device is supported but no longer recommended. Support will be deprecated in the future.
* *brick* - this image has been tested and found to brick your hardware. Avoid for now.
* *not supported* - this image is no longer supported and not available for download.

The 'target' and 'subtarget' identify the directory in which to find the image on at http://downloads.arednmesh.org

## Mikrotik (7)
Model | SKUs | Band | Target | Subtarget | Image | RAM | Stability | Status
:------ | :----: | :----: | :------: | :---------: | :-----: | :---: | :---------: | :------
hAP ac lite <br> hAP ac lite TC | RB952Ui-5ac2nD <br> RB952Ui-5ac2nD-TC | 2 & 5 | ath79 | mikrotik | mikrotik-952ui-5ac2nd | 64MB | stable | released
hAP ac² | RBD52G-5HacD2HnD-TC | 2 & 5 | ipq40xx | mikrotik | mikrotik_hap-ac2 | 128MB | stable | released
hAP ac³ | RBD53iG-5HacD2HnD | 2 & 5 | ipq40xx | mikrotik | mikrotik_hap-ac3 | 256MB | stable | released
SXTsq Lite2 | RBSXTsq2nD | 2 | ath79 | mikrotik | mikrotik-sxt-2nd | 64MB | stable | released
SXTsq Lite5 | RBSXTsq5nD | 5 | ath79 | mikrotik | mikrotik-sxt-5nd | 64MB | stable | released
SXTsq 5 High Power | RBSXTsq5HPnD | 5 | ath79 | mikrotik | mikrotik-sxt-5hpnd | 64MB | stable | released
SXTsq 5 ac | RBSXTsqG-5acD | 5 | ipq40xx | mikrotik | mikrotik_sxtsq-5-ac | 256MB | stable | released
LHG 2 | RBLHG-2nD | 2 | ath79 | mikrotik | mikrotik-lhg-2nd | 64MB | stable | released
LHG XL 2 | RBLHG-2nD-XL | 2 | ath79 | mikrotik | mikrotik-lhg-2nd-xl | 64MB | stable | released
LHG 5 | RBLHG-5nD | 5 | ath79 | mikrotik | mikrotik-lhg-5nd | 64MB | stable | released
LHG HP5 | RBLHG-5HPnD | 5 | ath79 | mikrotik | mikrotik-lhg-5hpnd | 64MB | stable | released
LHG XL HP5 | RBLHG-5HPnD-XL | 5 | ath79 | mikrotik | mikrotik-lhg-5hpnd-xl | 64MB | stable | released
LHG 5 ac | RBLHGG-5acD | 5 | ipq40xx | mikrotik | mikrotik_lhgg-5acd | 256MB | stable | released
LHG XL 5 ac | RBLHGG-5acD-XL | 5 | ipq40xx | mikrotik | mikrotik_lhgg-5acd-xl | 256MB | stable | released
LDF 2 | RBLDF-2nD | 2 | ath79 | mikrotik | mikrotik-ldf-2nd | 64MB | stable | released
LDF 5 | RBLDF-5nD | 5 | ath79 | mikrotik | mikrotik-ldf-5nd | 64MB | stable | released
LDF 5 ac | RBLDFG-5acD | 5 | ipq40xx | mikrotik | mikrotik-ldf-5acd | 64MB | stable | released
RB911G-2HPnD <br> mANTBox 2 12s | RB911G-2HPnD <br> RB911G-2HPnD-12S | 2 | ath79 | mikrotik | - | 64MB | untested | released
RB911G-5HPnD | RB911G-5HPnD | 5 | ath79 | mikrotik | - | 64MB | untested | released
QRT 5 | RB911G-5HPnD-QRT | 5 | ath79 | mikrotik | mikrotik-911g-5hpnd-qrt | 64MB | stable | released (1)
RB912UAG-2HPnD <br> BaseBox 2 | RB912UAG-2HPnD <br> RB912UAG-2HPnD-OUT | 2 | ath79 | mikrotik | mikrotik-912uag-2hpnd | 64MB | untested | released
RB912UAG-5HPnD <br> BaseBox 5 | RB912UAG-5HPnD <br> RB912UAG-5HPnD-OUT | 5 | ath79 | mikrotik | mikrotik-912uag-5hpnd | 64MB | stable | released (1)
RB922UAGS-5HPacD <br> NetMetal 5 | 922UAGS-5HPacD-NM <br> 922UAGS-5HPacD-NM-US | 5 | ath79 | mikrotik |  mikrotik_routerboard-922uags-5hpacd | 128MB | stable | nightly
mANTBox 15s | RB921GS-5HPacD-15S | 5 | ath79 | mikrotik | mikrotik-921gs-5hpacd-15s | 128MB | stable | released
mANTBox 19s | RB921GS-5HPacD-19S | 5 | ath79 | mikrotik | mikrotik-921gs-5hpacd-19s | 128MB | stable | released
mANTBox 2 12s | RB911G-2HPnD-12S | 2 | ath79 | mikrotik | mikrotik-911g-2hpnd-12s | 64MB | stable | released

## Ubiquiti
Model | SKUs | Band | Target | Subtarget | Image | RAM | Stability | Status
:------ | :----: | :----: | :------: | :---------: | :-----: | :---: | :---------: | :------
Bullet M2 XW || 2 | ath79 | generic | ubnt_bullet-m-xw | 64MB | untested | released
LiteAP 5AC | LAP-120 <br> LAP-120-US <br> LBE-5AC-16-120 <br> LBE-5AC-16-120-US | 5 | ath79 | generic | ubnt_lap-120 | 64MB | stable | released
LiteBeam 5AC Gen2 | LBE-5AC <br> LBE-5AC-US | 5 | ath79 | generic | ubnt_litebeam-ac-gen2 | 64MB | stable | released
LiteBeam 5AC LR | LBE-5AC-LR <br> LBE-5AC-LR-US | 5 | ath79 | generic | ubnt_litebeam-ac-lr | 64MB | stable | released
LiteBeam M5 || 5 | ath79 | - | - | 64MB | untested | not supported (8)
NanoBeam 2AC 13 (2WA) || 2 | ath79 | generic | ubnt_nanobeam-2ac-13 | 64MB | untested | not supported (8)
NanoBeam 5AC (WA) || 5 | ath79 | generic | ubnt_nanobeam-ac | 64MB | stable | released
NanoBeam 5AC (XC) || 5 | ath79 | generic | ubnt_nanobeam-ac-xc | 64MB | stable | released
NanoBeam 5AC Gen 2 (WA) || 5 | ath79 | generic | ubnt_nanobeam-ac-gen2 | 128MB | stable | released
NanoBeam 5AC Gen 2 (XC) || 5 | ath79 | generic | ubnt_nanobeam-ac-gen2-xc | 128MB | untested | released
NanoBeam M5-16 || 5 | ath79 | generic | ubnt_nanobeam-m5-16 | 64MB | stable | released
NanoBeam M5-19 || 5 | ath79 | generic | ubnt_nanobeam-m5-19 | 64MB | stable | released
NanoStation 5AC | NS-5AC <br> NS-5AC-US | 5 | ath79 | generic | ubnt_nanostation-ac | 64MB | stable | released
NanoStation Loco M2 XW || 2 | ath79 | generic | ubnt_nanostation-loco-m-xw | 64MB | untested | released
NanoStation Loco M5 XW || 5 | ath79 | generic | ubnt_nanostation-loco-m-xw | 64MB | stable | released
NanoStation M2 XW || 2 | ath79 | generic | ubnt_nanostation-m-xw | 64MB | stable | released
NanoStation M5 XW || 5 | ath79 | generic | ubnt_nanostation-m-xw | 64MB | stable | released
PowerBeam 5AC Gen2 || 5 | ath79 | generic | ubnt_powerbeam-5ac-gen2 | 128MB | untested | released
PowerBeam 5AC 400 || 5 | ath79 | generic | ubnt_powerbeam-5ac-400 | 128MB | untested | released
PowerBeam 5AC 500 | PBE-5AC-500 <br> PBE-5AC-500-US | 5 | ath79 | generic | ubnt_powerbeam-5ac-500 | 128MB | stable | released
PowerBeam 5AC 620 || 5 | ath79 | generic | ubnt_powerbeam-5ac-620 | 128MB | untested | released
PowerBeam-M2-400 || 2 | ath79 | generic | ubnt_powerbeam-m2-xw | 64MB | stable | released
PowerBeam-M5-300 || 5 | ath79 | generic | ubnt_powerbeam-m5-300 | 64MB | stable | released
PowerBeam-M5-400 || 5 | ath79 | generic | ubnt_powerbeam-m5-xw | 64MB | stable | released
PowerBeam-M5-400ISO || 5 | ath79 | generic | ubnt_powerbeam-m5-xw | 64MB | stable | released
PowerBeam-M5-620 || 5 | ath79 | generic | ubnt_powerbeam-m5-xw | 64MB | stable | released
PowerBridge || 5 | ath79 | generic | ubnt_powerbridge-m | 64MB | untested | released
Rocket 5AC Lite | R5AC-LITE <br> R5AC-LITE-US | 5 | ath79 | generic | ubnt_rocket-5ac-lite | 128MB | stable | released
Rocket M9 XM || 900 | ath79 | generic | ubnt_rocket-m | 64MB | stable | released
Rocket M2 XM || 2 | ath79 | generic | ubnt_rocket-m | 64MB | stable | released
Rocket M3 XM || 3 | ath79 | generic | ubnt_rocket-m | 64MB | stable | released
Rocket M5 XM || 5 | ath79 | generic | ubnt_rocket-m | 64MB | stable | released
Rocket M5GPS XM || 5 | ath79 | generic | ubnt_rocket-m | 64MB | stable | released
Rocket M2 XM with USB port || 2 | ath79 | generic | ubnt_rocket-m | 64MB | untested | released
Rocket M5 XM with USB port || 5 | ath79 | generic | ubnt_rocket-m | 64MB | untested | released
Rocket M2 XW || 2 | ath79 | generic | ubnt_rocket-m2-xw | 64MB | stable | released
Rocket M5 XW || 5 | ath79 | generic | ubnt_rocket-m-xw | 64MB | stable | released
Rocket M2 Titanium TI || 2 | ath79 | - | - | 64MB | untested | released
Rocket M2 Titanium XW || 2 | ath79 | generic | ubnt_rocket-m2-xw | 64MB | untested | released
Rocket M5 Titanium TI || 5 | ath79 | - | - | 64MB | untested | released
Rocket M5 Titanium XW || 5 | ath79 | generic | ubnt_rocket-m-xw | 64MB | stable | released
**Sunset Devices** | | | | | | | |
AirGrid M2 XM || 2 | ath79 | tiny (2) | ubnt_bullet-m-ar7241 | 32MB | untested | sunset
AirGrid M5 XM || 5 | ath79 | tiny (2) | ubnt_bullet-m-ar7241 | 32MB | untested | sunset
AirGrid M5 XW || 5 | ath79 | generic | ubnt_bullet-m-xw | 32MB | untested | sunset
AirRouter || 2 | ath79 | tiny (2) | ubnt_airrouter | 32MB | stable | sunset
AirRouter HP || 2 | ath79 | tiny (2) | ubnt_airrouter | 32MB | stable | sunset
Bullet M2Ti || 2 | ath79 | - | - | 32MB | untested | sunset
Bullet M5 || 5 | ath79 | tiny (2) | ubnt_bullet-m-ar7241 | 32MB | stable | sunset
Bullet M5Ti || 5 | ath79 | - | - | 32MB | untested | sunset
Bullet M2 || 2 | ath79 | tiny (2) | ubnt_bullet-m-ar7241 | 32MB | stable | sunset
NanoBeam M2-13 || 2 | ath79 | - | - | 32MB | untested | sunset
NanoBridge 2G18 || 2 | ath79 | tiny (2) | ubnt_nanobridge-m | 32MB | untested | sunset
NanoBridge 5G22 || 5 | ath79 | tiny (2) | ubnt_nanobridge-m | 32MB | stable | sunset
NanoBridge 5G25 || 5 | ath79 | tiny (2) | ubnt_nanobridge-m | 32MB | stable | sunset
NanoBridge M9 || 900 | ath79 | tiny (2) | ubnt_nanostation-loco-m | 32MB | stable | sunset
NanoStation Loco M2 XM || 2 | ath79 | tiny (2) | ubnt_nanostation-loco-m | 32MB | stable | sunset
NanoStation Loco M5 XM || 5 | ath79 | tiny (2) | ubnt_nanostation-loco-m | 32MB | untested | sunset
NanoStation Loco M9 XM || 900 | ath79 | tiny (2) | ubnt_nanostation-loco-m | 32MB | stable | sunset
NanoStation M2 XM || 2 | ath79 | tiny (2) | ubnt_nanostation-m | 32MB | stable | sunset
NanoStation M3 XM || 3 | ath79 | tiny (2) | ubnt_nanostation-m | 32MB | stable | sunset
NanoStation M5 XM || 5 | ath79 | tiny (2) | ubnt_nanostation-m | 32MB | stable | sunset
PicoStation M2 || 2 | ath79 | tiny (2) | ubnt_picostation-m | 32MB | untested | sunset

## TP-Link
Model | SKUs | Band | Target | Subtarget | Image | RAM | Stability | Status
:------ | :----: | :----: | :------: | :---------: | :-----: | :---: | :---------: | :------
TPLink CPE210 v1.X || 2 | ath79 | generic | tplink_cpe210-v1 | 64MB | stable | released
TPLink CPE210 v2.0 || 2 | ath79 | generic | tplink_cpe210-v2 | 64MB | stable | released
TPLink CPE210 v3.0 || 2 | ath79 | generic | tplink_cpe210-v3 | 64MB | untested | released
TPLink CPE220 v2.0 || 2 | ath79 | generic | tplink_cpe220-v2 | 64MB | untested | not supported
TPLink CPE220 v3.0 || 2 | ath79 | generic | tplink_cpe220-v3 | 64MB | untested | not supported
TPLink CPE510 v1.X || 5 | ath79 | generic | tplink_cpe510-v1 | 64MB | stable | released
TPLink CPE510 v2.0 || 5 | ath79 | generic | tplink_cpe510-v2 | 64MB | stable | released
TPLink CPE510 v3.0 || 5 | ath79 | generic | tplink_cpe510-v3 | 64MB | stable | released
TPLink CPE605 v1.0 || 5 | ath79 | generic | tplink_cpe605-v1 | 64MB | untested | released
TPLink CPE610 v1.0 || 5 | ath79 | generic | tplink_cpe610-v1 | 64MB | untested | released
TPLink CPE610 v2.0 || 5 | ath79 | generic | tplink_cpe610-v2 | 64MB | untested | released
TPLink CPE710 v1.0 | CPE710 V1.0 | 5 | ath79 | generic | tplink_cpe710-v1 | 128MB | stable | released
TPLink WBS210 v1.0 || 2 | ath79 | generic | tplink_wbs210-v1 | 64MB | untested | released
TPLink WBS210 v2.0 || 2 | ath79 | generic | tplink_wbs210-v2 | 64MB | untested | released
TPLink WBS510 v1.0 || 5 | ath79 | generic | tplink_wbs510-v1 | 64MB | untested | released
TPLink WBS510 v2.0 || 5 | ath79 | generic | tplink_wbs510-v2 | 64MB | untested | released

## GL.iNet
Model | SKUs | Band | Target | Subtarget | Image | RAM | Stability | Status
:------ | :----: | :----: | :------: | :---------: | :-----: | :---: | :---------: | :------
Shadow (16MB NOR) | GL-AR300M16 <br> GL-AR300M16-Ext | 2 | ath79 | generic | glinet_gl-ar300m16 | 64MB | stable | released
Shadow (128MB NAND) | GL-AR300M <br> GL-AR300M-Ext | 2 | ath79 | nand | gl-ar300m | 64MB | stable | released
Mudi | GL-E750 | 2 & 5 | ath79 | nand | gl-e750 | 128MB | stable | stable
Convexa-B | GL-B1300 | 2 & 5 | ipq40xx | generic | gl-b1300 | 256MB | stable | released (6)
Beryl | GL-MT1300 | 2 & 5 | ramips | mt7621 | gl-mt1300 | 256MB | stable | released (4)
**Sunset Devices** | | | | | | | |
White | GL-AR150 | 2 | ath79 | generic | glinet_gl-ar150 | 64MB | stable | sunset (3)
Microuter | GL-USB150 | 2 | ath79 | generic | glinet_gl-usb150 | 64MB | stable | sunset (3)
Creta | GL-AR750 | 2 | ath79 | generic | glinet_gl-ar750 | 128MB | stable | sunset (3)
Slate | GL-AR750S-Ext | 2 | ath79 | nand | gl-ar750s | 128MB | untested | sunset (3)

## Meraki
Model | SKUs | Band | Target | Subtarget | Image | RAM | Stability | Status
:------ | :----: | :----: | :------: | :---------: | :-----: | :---: | :---------: | :------
Meraki MR-16 | MR16-HW | 5 | ath79 | - | - | 64MB | unsupported | **brick**

## x86 / Virtual Machine

Hypervisor |  Target | Subtarget | Image | RAM | Stability | Status
:------ | :------: | :---------: | :-----: | :---: | :---------: | :------
Vmware ESXi  | x86 | 64 | x86-64-generic-ext4 | 64mb+ | stable | released (5)
Proxmox pve  | x86 | 64 | x86-64-generic-ext4 | 64mb+ | stable | released  (5)
Unraid | x86 |  64  | x86-64-generic-ext4 | 64mb+ | unsupported | released (5)


## Footnotes
 1. This device is supported for new installs. It can also be upgraded from 3.22.12.0 after first installing the [DangerousUpgrade package](https://github.com/kn6plv/DangerousUpgrade/raw/main/dangerousupgrade_0.1_all.ipk) to disable the firmware compatibility checks. Proceed carefully.
 2. Tiny builds exclude support for *tunnels* and *WiFi AP* mode due to lack of resources. The relevant packages can be installed separately but this is not recommended.
 3. These devices are no longer being manufactured by GL-iNET. They may not reboot reliably and you may need to power cycle them (several times) during an update.
 4. 20MHz channels only.
 5. x86 images are for advanced users. See "Installing AREDN® Firmware" x86 documentation section.
 6. These devices do not function on negative channels in the 2.4 GHz band.
 7. Mikrotik devices come with either a v6 bootloader or a v7 bootloader. See [here](https://openwrt.org/toh/mikrotik/common) for more details. If you are using a v7 bootloader use the v7 sysupgrade instead of the plain one.
 8. These devices were supported in older releases, but not supported in the current one.

Latest installation instructions are found at: https://docs.arednmesh.org/en/latest/
