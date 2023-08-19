if nixio.fs.stat("/tmp/supernode.dns") then
    local ip = read_all("/tmp/supernode.dns"):match("^(%S+)")
    if ip then
        return { href = "http://" .. ip .. "/cgi-bin/mesh", display = "Super Mesh", hint = "See what is on the supernode mesh" }
    end
end
