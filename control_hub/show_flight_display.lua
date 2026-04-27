local args = {...}

local function loadDisplay(name)
    local path = "display/" .. name .. ".lua"
    local fn, err = loadfile(path)
    if not fn then
        error("Could not load display module [" .. name .. "]: " .. tostring(err), 0)
    end
    return fn()
end

local core = loadDisplay("core")
local device = loadDisplay("device")
local flight = loadDisplay("flight")

if not args[1] then
    print("Usage: show_flight_display.lua <displaySide> [textScale]")
    print("Example: show_flight_display.lua left 1")
    return
end

local side = args[1]
local textScale = tonumber(args[2]) or 1

if textScale <= 0 then
    print("ERROR: Invalid text scale.")
    return
end

local screen, screenErr = device.wrap(side)
if not screen then
    print("ERROR: " .. tostring(screenErr))
    return
end

core.configure(screen, textScale)
flight.draw(screen, {}, "NO FLIGHT DATA")
