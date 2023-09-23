if nixio.fs.stat("/tmp/dnsmasq.d/supernode.conf") then
    local ip = read_all("/tmp/dnsmasq.d/supernode.conf"):match("^#(%S+)")
    if ip then
        return { href = "http://" .. ip .. "/cgi-bin/mesh", display = "Super Mesh", hint = "See what is on the whole AREDN mesh" }
    end
end
