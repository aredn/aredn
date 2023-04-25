return { href = "vpnc", display = "Tunnel<br>Client", enable = nixio.fs.stat("/usr/sbin/vtund") ~= nil }
