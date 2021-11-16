
local http = require("socket.http")
local json = require("luci.jsonc")

utils = {}

function utils.read_all(filename)
    local lines = {}
    for line in io.lines(filename)
    do
        lines[#lines + 1] = line
    end
    return lines
end

function utils.write_all(filename, data)
    local f = io.open(filename, "w")
    if f then
        f:write(data)
        f:close()
    end
end

function utils.system_run(cmd)
    local f = io.popen(cmd, "r")
    if f then
        local lines = {}
        for line in f:lines()
        do
            lines[#lines + 1] = line
        end
        f:close()
        return lines
    end
    return nil
end

function utils.split(str, sep)
    if not str then
        return {}
    end
    if not sep then
        sep = "%s"
    end
    local r = {}
    local p = "([^" .. sep .. "]+)"
    for s in string.gmatch(str, p)
    do
        r[#r + 1] = s
    end
    return r
end

function utils.uptime()
    return math.floor(utils.split(utils.read_all("/proc/uptime")[1])[1])
end

function utils.fetch_json(url)
    resp, status_code, headers, status_message = http.request(url)
    if status_code == 200 then
        return json.parse(resp)
    else
        return nil
    end
end

function utils.get_board_type()
    local json = json.parse(table.concat(utils.read_all("/etc/board.json")))
    return json.model.id;
end

utils.log = {}
utils.log.__index = utils.log

function utils.log.start(name, maxlines)
    local l = {}
    setmetatable(l, utils.log)
    l.logfile = name
    l.logmax = maxlines
    l.logf = nil
    return l
end

function utils.log:write(str)
    if not self.logf then
        self.logf = io.open(self.logfile, "a")
    end
    self.logf:write("%s: %s\n", os.date("%m/%d %H:%M:%S", os.time()), str)
end

function utils.log:flush()
    if self.logf then
        self.logf:close()
        self.logf = nil
        file_trim(self.logfile, self.logmax)
    end
end
