/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2022-2025 Tim Wilkinson
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

function findSpecialDomains(needSupernodes)
{
    let subdomains = "";
    const supernodes = [];
    const reWildcard = /^([0-9\.]+)[ \t]+\*\.([^ \t]+)$/;
    const reSupernode = /^([0-9\.]+)[ \t]+supernode\.([^ \t]+)$/;
    const dir = fs.opendir("/var/run/arednlink/hosts");
    for (;;) {
        const entry = dir.read();
        if (!entry) {
            break;
        }
        if (entry !== "." && entry !== "..") {
            const f = fs.open(`/var/run/arednlink/hosts/${entry}`);
            if (f) {
                for (let line = f.read("line"); length(line); line = f.read("line")) {
                    line = trim(line);
                    const m = match(line, reWildcard);
                    if (m) {
                        subdomains += `address=/.${m[2]}/${m[1]}\n`;
                    }
                    else if (needSupernodes) {
                        const m = match(line, reSupernode);
                        if (m) {
                            push(supernodes, { name: m[2], ip: m[1], metric: 99999999 });
                        }
                    }
                }
                f.close();
            }
        }
    }
    dir.close();
    return { subdomains: subdomains, supernodes: supernodes };
}

function findBestSupernodes(supernodes)
{
    if (length(supernodes) === 0) {
        return null;
    }
    if (length(supernodes) === 1) {
        return supernodes;
    }
    const routes = babel.getHostRoutes();
    for (let i = 0; i < length(routes); i++) {
        const r = routes[i];
        for (let j = 0; j < length(supernodes); j++) {
            const s = supernodes[j];
            if (r.dst == s.ip && r.metric < s.metric) {
                s.metric = r.metric;
            }
        }
    }
    sort(supernodes, (a, b) => a.metric - b.metric);
    return supernodes;
}

function updateSubdomains(subdomains)
{
    const osubdomains = fs.readfile("/tmp/dnsmasq.d/subdomains.conf");
    if (osubdomains == subdomains) {
        return false;
    }
    fs.writefile("/tmp/dnsmasq.d/subdomains.conf", subdomains);
    return true;
}

function updateSupernodes(supernodes)
{
    let dns = "";
    const ips = [];
    if (supernodes) {
        dns += `#${supernodes[0].name}\n`;
        dns += "all-servers\n";
        for (let i = 0; i < 2 && i < length(supernodes); i++) {
            const ip = supernodes[i].ip;
            push(ips, ip);
            dns += `server=/local.mesh/${ip}\nrev-server=10.0.0.0/8,${ip}\n`;
        }
    }
    const f = fs.open("/etc/44net.conf");
    if (f) {
        for (let line = f.read("line"); length(line); line = f.read("line")) {
            line = trim(line);
            for (let i = 0; i < length(ips); i++) {
                dns += `rev-server=${line},${ips[i]}\n`;
            }
        }
        f.close();
    }
    const odns = fs.readfile("/tmp/dnsmasq.d/supernode.conf");
    if (odns == dns) {
        return false;
    }
    fs.writefile("/tmp/dnsmasq.d/supernode.conf", dns);
    return true;
}

return function()
{
    let needSupernodes = false;
    const c = uci.cursor();
    if (c.get("aredn", "@supernode[0]", "enable") != "1" && c.get("aredn", "@supernode[0]", "support") != "0") {
        needSupernodes = true;
    }
    const finds = findSpecialDomains(needSupernodes);
    const changed1 = updateSubdomains(finds.subdomains);
    const changed2 = updateSupernodes(findBestSupernodes(finds.supernodes));
    if (changed1 || changed2) {
        system("/etc/init.d/dnsmasq restart");
    }
    return waitForTicks(300);
};
