local args = {...}
local command = args[1]
local unpackValues = table.unpack or unpack

local function usage()
    print("Usage:")
    print("display.lua dashboard [side] [period] [scale]")
    print("display.lua airspeed <side> [period] [scale]")
    print("display.lua flight <side> [scale]")
end

local function runScript(path, forwarded)
    local fn, err = loadfile(path)
    if not fn then
        print("ERROR: Could not load script [" .. tostring(path) .. "]: " .. tostring(err))
        return
    end

    fn(unpackValues(forwarded))
end

local function tail(startIndex)
    local result = {}
    for i = startIndex, #args do
        result[#result + 1] = args[i]
    end
    return result
end

if not command then
    usage()
elseif command == "dashboard" then
    runScript("display_dashboard.lua", tail(2))
elseif command == "airspeed" then
    runScript("monitor_airspeed.lua", tail(2))
elseif command == "flight" then
    runScript("show_flight_display.lua", tail(2))
else
    print("ERROR: Unknown display command [" .. tostring(command) .. "]")
    usage()
end
