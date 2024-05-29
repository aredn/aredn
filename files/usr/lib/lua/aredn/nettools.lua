#!/usr/bin/lua
--[[

	Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2019 Darryl Quinn
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

	Additional use restrictions exist on the AREDN® trademark and logo.
		See AREDNLicense.txt for more info.

	Attributions to the AREDN® Project must be retained in the source code.
	If importing this code into a new or existing project attribution
	to the AREDN® project must be added to the source code.

	You must not misrepresent the origin of the material contained within.

	Modified versions must be modified to attribute to the original source
	and be marked in reasonable ways as differentiate it from the original
	version.

--]]

require("aredn.utils")

local tools = {}

-------------------------------------
-- Returns traceroute
-------------------------------------
function tools.getTraceroute(target)
	local info={}
	local routes={}
	local trall=capture('/bin/traceroute -q1 ' .. target )
	local lines = trall:splitNewLine()

	table.remove(lines, 1)	-- remove heading
	table.remove(lines, #lines) -- remove blank last line

	local data = {}
	local priortime = 0
	for i,v in pairs(lines) do
		data = v:splitWhiteSpace()
		entry = {}
		if data[2] ~= "*" then
			node = data[2]:gsub("^mid[0-9]*%.","") 	-- strip midXX.
			node = node:gsub("^dtdlink%.","")		-- strip dtdlink.
			node = node:gsub("%.local%.mesh$","")	-- strip .local.mesh
			entry['nodename'] = node
			ip = data[3]:match("%((.*)%)")
			entry['ip'] = ip
			entry['timeto'] = round2(data[4])
			entry['timedelta'] = math.abs(round2(data[4] - priortime))
			priortime = round2(data[4])
			table.insert(routes, entry)
		end
	end
	return routes
end

-------------------------------------
-- Returns ping
-------------------------------------
function tools.getPing(target)
	local pings = {}
	local summary = { tx = -1, rx = -1, lossPercentage = -1, ip = "not found", minMs = -1, maxMs = -1, avgMs = -1 }
	local output = capture("/bin/ping -w 10 " .. target)
	local foundip = "unknown"
	for _, line in ipairs(output:splitNewLine())
	do
		local ip = line:match("^PING %S+ %(([%d%.]+)%):")
		if ip then
			summary.ip = ip
		else
			local ip, seq, ttl, time = line:match("bytes from ([%d%.]+): seq=(%d+) ttl=(%d+) time=(%S+) ms")
			if ip then
				pings[#pings + 1] = { ip = ip, seq = tonumber(seq), ttl = tonumber(ttl), timeMs = tonumber(time) }
			else
				local tx, rx, loss = line:match("^(%d+) packets transmitted, (%d+) packets received, (%d+)%% packet loss")
				if tx then
					summary.tx = tonumber(tx)
					summary.rx = tonumber(rx)
					summary.lossPercentage = tonumber(loss)
				else
					local min, avg, max = line:match("min/avg/max = ([%d%.]+)/([%d%.]+)/([%d%.]+) ms")
					if min then
						summary.minMs = tonumber(min)
						summary.maxMs = tonumber(max)
						summary.avgMs = tonumber(avg)
					end
				end
			end
		end
	end
	return { summary = summary, pings = pings }
end

-------------------------------------
-- Returns iperf3
-------------------------------------
function tools.getIperf3(target, protocol)
	if protocol ~= "udp" then
		protocol = "tcp"
	end
	function toK(value, unit)
		return tonumber(value) * (unit == "M" and 1024 or 1)
	end
	function toM(value, unit)
		return tonumber(value) / (unit == "K" and 1024 or 1)
	end
	local summary = { protocol = protocol, client = {}, server = {}, sender = {}, receiver = {} }
	local trace = {}
	-- start remote server
	local output = capture("/usr/bin/wget -q -O - 'http://localhost:8080/cgi-bin/iperf?server=" .. target .. "&protocol=" .. protocol .. "'")
	for _, line in ipairs(output:splitNewLine())
	do
		if line:match("<title>CLIENT DISABLED</title>") then
			summary.error = "client disabled"
		elseif line:match("<title>SERVER DISABLED</title>") then
			summary.error = "server disabled"
		elseif line:match("<title>BUSY</title>") then
			summary.error = "busy"
		else
			local chost, cport, shost, sport = line:match("local ([%d%.]+) port (%d+) connected to ([%d%.]+) port (%d+)")
			if chost then
				summary.client = { host = chost, port = tonumber(cport) }
				summary.server = { host = shost, port = tonumber(sport) }
			else
				local from, to, transfer, tu, bitrate, bu, retr = line:match("([%d%.]+)-([%d%.]+)%s+sec%s+([%d%.]+) ([KM])Bytes%s+([%d%.]+) ([MK])bits/sec%s+(%d+)%s+sender")
				if from then
					summary.sender = { from = tonumber(from), to = tonumber(to), transferMB = toM(transfer, tu), bitrateMb = toM(bitrate, bu), retr = tonumber(retr) }
				else
					local from, to, transfer, tu, bitrate, bu = line:match("([%d%.]+)-([%d%.]+)%s+sec%s+([%d%.]+) ([KM])Bytes%s+([%d%.]+) ([MK])bits/sec%s+receiver")
					if from then
						summary.receiver = { from = tonumber(from), to = tonumber(to), transferMB = toM(transfer, tu), bitrateMb = toM(bitrate, bu) }
					else
						local from, to, transfer, tu, bitrate, bu, jitter, lost, total, percent = line:match("([%d%.]+)-([%d%.]+)%s+sec%s+([%d%.]+) ([KM])Bytes%s+([%d%.]+) ([MK])bits/sec%s+([%d%.]+) ms%s+(%d+)/(%d+) %(([%d%.]+)%%%)%s+sender")
						if from then
							summary.sender = { from = tonumber(from), to = tonumber(to), transferMB = toM(transfer, tu), bitrateMb = toM(bitrate, bu), jitterMs = tonumber(jitter), lostDgrams = tonumber(lost), totalDgrams = tonumber(total), lossPercentage = tonumber(precent) }
						else
							local from, to, transfer, tu, bitrate, bu, jitter, lost, total, percent = line:match("([%d%.]+)-([%d%.]+)%s+sec%s+([%d%.]+) ([KM])Bytes%s+([%d%.]+) ([MK])bits/sec%s+([%d%.]+) ms%s+(%d+)/(%d+) %(([%d%.]+)%%%)%s+receiver")
							if from then
								summary.receiver = { from = tonumber(from), to = tonumber(to), transferMB = toM(transfer, tu), bitrateMb = toM(bitrate, bu), jitterMs = tonumber(jitter), lostDgrams = tonumber(lost), totalDgrams = tonumber(total), lossPercentage = tonumber(precent) }
							else
								local from, to, transfer, tu, bitrate, bu, retr, cwnd, cu = line:match("([%d%.]+)-([%d%.]+)%s+sec%s+([%d%.]+) ([KM])Bytes%s+([%d%.]+) ([MK])bits/sec%s+(%d+)%s+([%d%.]+) ([KM])Bytes")
								if from then
									trace[#trace + 1] = { from = tonumber(from), to = tonumber(to), transferMB = toM(transfer, tu), bitrateMb = toM(bitrate, by), retr = tonumber(retr), cwndKB = toK(cwnd, cu) }
								else
									local from, to, transfer, tu, bitrate, bu, dgrams = line:match("([%d%.]+)-([%d%.]+)%s+sec%s+([%d%.]+) ([KM])Bytes%s+([%d%.]+) ([MK])bits/sec%s+(%d+)")
									if from then
										trace[#trace + 1] = { from = tonumber(from), to = tonumber(to), transferMB = toM(transfer, tu), bitrateMb = toM(bitrate, bu), dgrams = tonumber(dgrams) }
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return { summary = summary, trace = trace }
end

if not aredn then
    aredn = {}
end
aredn.nettools = tools
return tools
