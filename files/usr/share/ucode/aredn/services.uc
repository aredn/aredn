/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2021-2025 Tim Wilkinson
 * Original Perl Copyright (C) 2015 Conrad Lara
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

import * as fs from "fs";
import * as uci from "uci";
import * as socket from "socket";
import * as configuration from "aredn.configuration";
import * as network from "aredn.network";

// Whether to validate hosts and services before publishing
const validation_timeout = 150 * 60; // 2.5 hours (so must fail 3 times in a row)
const validation_state = "/tmp/service-validation-state.json";

const pubsubbase = "/etc/arednlink";
const allpubsubbase = "/var/run/arednlink";

export function get(validate)
{
    const names = [];
    let hosts = [];
    let services = [];

    const cm = uci.cursor("/etc/config.mesh");

    // canonical names for this node
    // (they should up in reverse order, make the official name last)
    let name = configuration.getName();
    if (name) {
        push(names, name);
        if (cm.get("aredn", "@supernode[0]", "enable") == "1") {
            push(names, `supernode.${name}.local.mesh`);
        }
    }

    const dmz_mode = cm.get("setup", "globals", "dmz_mode");
    if (dmz_mode != "0") {
        const aliases = cm.get("setup", "aliases", "alias");
        if (aliases) {
            for (let i = 0; i < length(aliases); i++) {
                const m = match(aliases[i], /([^ \t]+)[ \t]+([^ \t]+)/);
                if (m) {
                    push(hosts, { ip: m[1], host: `${m[2]}${index(m[2], ".") === -1 ? "" : ".local.mesh"}` });
                }
            }
        }
        if (fs.access("/etc/ethers") && fs.access("/etc/hosts")) {
            const nopropip = {};
            const etchosts = {};
            let p = fs.open("/etc/hosts");
            for (let line = p.read("line"); length(line); line = p.read("line")) {
                const m = match(trim(line), /^([0-9\.]+)[ \t]+([^ \t]+)[^#]*(#NOPROPS|#ALIAS)?$/);
                if (m && m[3] !== "#ALIAS") {
                    etchosts[m[1]] = m[2];
                    nopropip[m[1]] = m[3] === "#NOPROPS";
                }
            }
            p.close();
            p = fs.open("/etc/ethers");
            for (let line = p.read("line"); length(line); line = p.read("line")) {
                const m = match(line, /[0-9a-fA-F:]+[ \t]+([0-9\.]+)/);
                if (m && !nopropip[m[1]]) {
                    const host = etchosts[m[1]] || network.getHostnameFromIPAddress(m[1]);
                    if (host) {
                        const shost = replace(host, /\.local\.mesh$/, "");
                        if (index(shost, ".") === -1) {
                            push(hosts, { ip: m[1], host: shost });
                        }
                        else {
                            push(hosts, { ip: m[1], host: host });
                        }
                    }
                }
            }
        }
    }
    
    // add a name for the dtdlink and xlink interfaces
    if (name) {
        const f = fs.open("/etc/hosts");
        if (f) {
            for (let line = f.read("line"); length(line); line = f.read("line")) {
                let m = match(line, /^(\d+\.\d+\.\d+\.\d+)[ \t]+dtdlink\./);
                if (m) {
                    push(hosts, { ip: m[1], host: `dtdlink.${name}.local.mesh` });
                }
                m = match(trim(line), /^(\d+\.\d+\.\d+\.\d+)[ \t]+localnode$/);
                if (m) {
                    push(hosts, { ip: m[1], host: `lan.${name}.local.mesh` });
                }
            }
            f.close();
        }
        if (fs.access("/etc/config.mesh/xlink")) {
            let count = 0;
            cm.foreach("xlink", "interface",
                function(section) {
                    if (section.ipaddr) {
                        push(hosts, { ip: section.ipaddr, host: `xlink${count}.${name}.local.mesh` });
                        count++;
                    }
                }
            );
        }
    }

    // load the services
    const svcs = cm.get("setup", "services", "service");
    if (svcs) {
        for (let i = 0; i < length(svcs); i++) {
            const m = match(svcs[i], /(.*)\|(.*)\|(.*)\|(.*)\|(.*)\|(.*)/);
            if (m && m[1] && m[4]) {
                const proto = m[3] ? m[3] : "http";
                const port = m[2] == "0" ? "0" : m[5];
                push(services, `${proto}://${m[4]}:${port}/${m[6]}|tcp|${m[1]}`);
            }
        }
    }

    // Validation
    if (validate) {
        const vstate = fs.access(validation_state) ? json(fs.readfile(validation_state)).valid : {};
        const now = clock(true)[0];
        const last = now + validation_timeout;

        // Add in local names so services pass
        for (let i = 0; i < length(names); i++) {
            vstate[lc(names[i])] = last;
        }

        // Check we can reach all the IP addresses
        for (let i = 0; i < length(hosts); i++) {
            const host = hosts[i];
            if (system(`/bin/ping -q -c 1 -W 1 ${host.ip} > /dev/null 2>&1`) == 0) {
                vstate[lc(host.host)] = last;
                push(services, `pseudo://${host.host}:80/|tcp|pseudo`);
                push(services, `pseudo://${host.host}:443/|tcp|pseudo`);
            }
            else if (system(`/usr/sbin/arping -q -f -c 1 -w 1 -I br-lan ${host.ip} > /dev/null 2>&1`) == 0) {
                vstate[lc(host.host)] = last;
                push(services, `pseudo://${host.host}:80/|tcp|pseudo`);
                push(services, `pseudo://${host.host}:443/|tcp|pseudo`);
            }
        }

        // Load NAT
        let nat = null;
        if (dmz_mode == "0") {
            const ports = cm.get("setup", "ports", "port");
            if (ports) {
                nat = {};
                const lname = `${lc(name)}.local.mesh`;
                for (let i = 0; i < length(ports); i++) {
                    const line = ports[i];
                    const m = match(line, /^(.+):(.+):(.+):(.+):(\d+):(\d)$/);
                    if (m && m[6] == "1") {
                        const type = m[2];
                        const addr = m[4];
                        let sp = int(m[3]);
                        let ep = sp;
                        const mm = match(m[3], /^(\d+)\-(\d+)$/);
                        if (mm) {
                            sp = int(mm[1]);
                            ep = int(mm[2]);
                        }
                        const dport = int(m[5]);
                        for (let p = sp; p <= ep; p++) {
                            if (type == "udp" || type == "both") {
                                nat[`${lname}:udp:${p}`] = { hostname: addr, port: dpor + p - sp };
                            }
                            if (type == "tcp" || type == "both") {
                                nat[`${lname}:tcp:${p}`] = { hostname: addr, port: dpor + p - sp };
                            }
                        }
                    }
                }
            }
        }
        // Check all the service haev a valid host
        const havecurl = fs.access("/usr/bin/curl");
        for (let i = 0; i < length(services); i++) {
            const service = services[i];
            const m = match(service, /^([a-zA-Z0-9]+):\/\/([a-zA-Z0-9\.\-]+):(\d+)(.*)\|...\|[^|]+$/);
            if (m) {
                const proto = m[1];
                let hostname = m[2];
                let port = int(m[3]);
                const path = m[4];
                const vs = vstate[lc(hostname)];
                if (!vs || vs > now || dmz_mode == "0") {
                    if (port == "0") {
                        // no port so not a link - we can only check the hostname so have to assume the service is good
                        vstate[service] = last;
                    }
                    else if (havecurl && (proto == "http" || (proto == "pseudo" && port == "80"))) {
                        // http so looks like a link. http check it
                        if (!match(hostname, /\./)) {
                            hostname += ".local.mesh";
                        }
                        // nat translation
                        const n = nat ? nat[`${lc(hostname)}:tcp:${port}`] : null;
                        if (n) {
                            hostname = n.hostname;
                            port = n.port;
                        }
                        let u = `http://${hostname}:${port}${path}`;
                        // Curl wont handle any auth after a redirect, so we do that manually here instead.
                        if (index(path, "/a/redirect?") === 0) {
                            u = substr(path, 12);
                        }
                        const cf = fs.popen(`/usr/bin/curl --max-time 10 --retry 0 --connect-timeout 2 --speed-time 10 --speed-limit 1000 --silent --output /dev/null --cookie-jar /tmp/service-test-cookies --location --write-out '%{http_code} %{url_effective}' ${u}`);
                        if (cf) {
                            const all = cf.read("all");
                            cf.close();
                            fs.unlink("/tmp/service-test-cookies");
                            const m = match(all, /^(\d+) (.*)/);
                            if (m[1] == "200" || m[1] == "401") {
                                vstate[service] = last;
                            }
                            else if (m[1] == "301" || m[1] == "302" || m[1] == "303" || m[1] == "307" || m[1] == "308") {
                                // Ended at a redirect rather than an actual page.
                                if (match(m[2], /^https:/)) {
                                    // We cannot validate https: links so we just assume they're okay
                                    vstate[service] = last;
                                }
                            }
                        }
                    }
                    else {
                        function hostname2ip(hostname)
                        {
                            hostname = lc(hostname);
                            for (let i = 0; i < length(hosts); i++) {
                                if (lc(hosts[i].host) == hostname) {
                                    return hosts[i].ip;
                                }
                            }
                            return null;
                        }
                        // valid port, but we dont know the protocol (we cannot trust the one defined in the services file because the UI wont set
                        // anything but 'tcp'). Check both tcp and udp and assume valid it either is okay
                        let sock = socket.create(socket.AF_INET, socket.SOCK_STREAM, 0);
                        sock.setopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, { tv_sec: 2, tv_usec: 0 });
                        const n = nat ? nat[`${lc(hostname)}:tcp:${port}`] : null;
                        let r;
                        if (n) {
                            r = sock.connect(hostname2ip(n.hostname), n.port);
                        }
                        else {
                            r = sock.connect(hostname2ip(hostname), port);
                        }
                        sock.close();
                        if (r) {
                            // tcp connection succeeded
                            vstate[service] = last;
                        }
                        else {
                            // udp
                            sock = socket.create(socket.AF_INET, socket.SOCK_DGRAM, 0);
                            const n = nat ? nat[`${lc(hostname)}:udp:${port}`] : null;
                            if (n) {
                                sock.connect(hostname2ip(n.hostname), n.port);
                            }
                            else {
                                sock.connect(hostname2ip(hostname), port);
                            }
                            sock.send("");
                            r = socket.poll(1, [ sock, socket.POLLIN|socket.POLLERR ]);
                            sock.close();
                            if (!(r[0][1] & socket.POLLERR)) {
                                // An error response is an explicity rejection of the udp request. Otherwise we have
                                // to assume the service is valid
                                vstate[service] = last;
                            }
                        }
                    }
                }
            }
        }

        // Generate new hosts and services as long as they're valid
        const old_hosts = hosts;
        hosts = [];
        for (let i = 0; i < length(old_hosts); i++) {
            const host = old_hosts[i];
            const lname = lc(host.host);
            const vs = vstate[lname];
            if (!vs) {
                push(hosts, host);
                vstate[lname] = last;
            }
            else if (vs > now) {
                push(hosts, host);
            }
        }
        const old_services = services;
        services = [];
        for (let i = 0; i < length(old_services); i++) {
            const service = old_services[i];
            if (!match(service, /^pseudo:/)) {
                const vs = vstate[service];
                if (!vs) {
                    // New services will be valid for a while, even if they're not there yet
                    push(services, service);
                    vstate[service] = last;
                }
                else if (vs > now) {
                    push(services, service);
                }
            }
        }

        // Store state for next time
        fs.writefile(validation_state, sprintf("%.2J", {
            when: now,
            valid: vstate
        }));
    }

    return {
        names: names,
        hosts: hosts,
        services: services
    };
};

export function resetValidation()
{
    fs.unlink(validation_state);
};

function add(pubsub, id, topic, data)
{
    if (id && topic && data) {
        const f = fs.open(`${pubsubbase}/${pubsub}`, "r+");
        if (f) {
            try {
                f.lock("x");
                const info = json(f.read("all") || '{"v1":[]}');
                for (let i = 0; i < length(info.v1); i++) {
                    if (info.v1[i].id == id) {
                        splice(info.v1, i, 1);
                        break;
                    }
                }
                push(info.v1, { id: id, topic: topic, data: data });
                f.seek();
                f.write(sprintf("%J", info));
                f.truncate(f.tell());
                f.lock("u");
                f.close();
                system(`echo "upload ${pubsub} ${pubsubbase}/${pubsub}" | socat -T 5 UNIX-CLIENT:/var/run/arednlink.sock - 2>&1 > /dev/null;`);
                return true;
            }
            catch (_) {
            }
            f.lock("u");
            f.close();
        }
    }
    return null;
}

function remove(pubsub, id)
{
    const f = fs.open(`${pubsubbase}/${pubsub}`, "r+");
    if (f) {
        try {
            f.lock("x");
            const info = json(f.read("all"));
            for (let i = 0; i < length(info.v1); i++) {
                if (info.v1[i].id == id) {
                    splice(info.v1, i, 1);
                    f.seek();
                    if (length(info.v1)) {
                        f.write(sprintf("%J", info));
                    }
                    f.truncate(f.tell());
                    f.lock("u");
                    f.close();
                    system(`echo "upload ${pubsub} ${pubsubbase}/${pubsub}" | socat -T 5 UNIX-CLIENT:/var/run/arednlink.sock - 2>&1 >/dev/null`);
                    return true;
                }
            }
        }
        catch (_) {
        }
        f.lock("u");
        f.close();
    }
    return false;
}

export function publish(id, topic, data)
{
    return add("publish", id, topic, data);
};

export function unpublish(id)
{
    return remove("publish", id);
};

function getByTopic(root, topic, targets)
{
    const results = [];
    const topicbase = substr(topic, -1) === "*" ? substr(topic, 0, -1) : null;
    const files = targets ? targets : fs.lsdir(root);
    if (files) {
        for (let i = 0; i < length(files); i++) {
            const file = `${root}/${files[i]}`;
            if (fs.lstat(file).size) {
                try {
                    const f = fs.open(file);
                    if (f) {
                        f.lock("s");
                        const filedata = f.read("all");
                        f.lock("u");
                        f.close();
                        const j = json(filedata);
                        for (let i = 0; i < length(j.v1 ?? []); i++) {
                            const t = j.v1[i].topic;
                            if (t === topic || (topicbase && index(t, topicbase) === 0)) {
                                push(results, j.v1[i].data);
                            }
                        }
                    }
                }
                catch (_) {
                }
            }
        }
    }
    return results;
}

export function published(topic, targets)
{
    return getByTopic(`${allpubsubbase}/publish`, topic, targets);
};

const watchers = {};

export function watch(type)
{
    const f = fs.popen(`echo $$;exec /usr/bin/inotifywait --monitor --quiet --format '%w%f' --event close_write /var/run/arednlink/${type ?? "publish"}/`);
    watchers[f] = f.read("line");
    return f;
};

export function unwatch(handle)
{
    const pid = watchers[handle];
    if (pid) {
        system(`/bin/kill -9 ${pid}`);
        handle.close();
    }
};

