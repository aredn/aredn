/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2026 Tim Wilkinson
 * See Contributors file for additional contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation version 3 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Additional Terms:
 *
 * Additional use restrictions exist on the AREDN® trademark and logo.
 * See AREDNLicense.txt for more info.
 *
 * Attributions to the AREDN® Project must be retained in the source code.
 * If importing this code into a new or existing project attribution
 * to the AREDN® project must be added to the source code.
 *
 * You must not misrepresent the origin of the material contained within.
 *
 * Modified versions must be modified to attribute to the original source
 * and be marked in reasonable ways as differentiate it from the original
 * version
 */

if (uci.cursor().get("aredn", "@remote_rf[0]", "enable") != "1") {
    return exitApp();
}

return function()
{
    const addvlan = {};
    const rmvlan = {};

    // Get the list of active remote wifi vlans
    lqm.reset();
    const trackers = lqm.getTrackers();
    for (let mac in trackers) {
        const tracker = trackers[mac];
        if (tracker.wifivlans) {
            map(tracker.wifivlans, vlan => addvlan[`${vlan}`] = true);
        }
    }

    // Get the current set and work out which ones to add or remove
    const c = uci.cursor();
    c.foreach("network", "interface", i => {
        const name = i[".name"];
        if (substr(name, 0, 8) === "remoterf") {
            const vlan = substr(name, 10);
            if (addvlan[vlan]) {
                delete addvlan[vlan];
            }
            else {
                rmvlan[vlan] = true;
            }
        }
    });

    let changed = false;
    const dtdports = map(hardware.getBoardNetworkInterfaceName("dtdlink"), p => `${split(p, ".")[0]}:t`);
    for (let vlan in addvlan) {
        const name = `remoterf${vlan}`;
        const bname = `${name}bridge`;
        c.set("network", bname, "bridge-vlan");
        c.set("network", bname, "device", "br0");
        c.set("network", bname, "vlan", vlan);
        c.set("network", bname, "ports", dtdports);
        c.set("network", bname, "macaddr", replace("x2:xx:xx:xx:xx:xx", "x", _ => sprintf("%x",math.rand()&15)));
        c.set("network", name, "interface");
        c.set("network", name, "ifname", `br0.${vlan}`);
        changed = true;
        log.syslog(log.LOG_NOTICE, `Adding remote wifi: vlan ${vlan}`);
    }
    for (vlan in rmvlan) {
        const name = `remoterf${vlan}`;
        const bname = `${name}bridge`;
        c.delete("network", bname);
        c.delete("network", name);
        changed = true;
        log.syslog(log.LOG_NOTICE, `Removing remote wifi: vlan ${vlan}`);
    }
    if (changed) {
        c.commit("network");
        system("/etc/init.d/network reload");
    }

    return waitForTicks(60);
};
