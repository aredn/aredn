if nixio.fs.stat("/tmp/dnsmasq.d/supernode.conf") then
    local ip = read_all("/tmp/dnsmasq.d/supernode.conf"):match("^#(%S+)")
    if ip then
        return { href = "http://" .. ip .. "/cgi-bin/mesh", display = "Super Mesh", hint = "See what is on the supernode mesh" }
    end
elseif uci.cursor():get("aredn", "@supernode[0]", "enable") == "1" then
    return { href = "/cgi-bin/mesh", display = "Super Mesh", hint = "See what is on the supernode mesh" }
end
