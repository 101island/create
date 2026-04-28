local args = {...}

local function loadDisplay(name)
    local path = "display/" .. name .. ".lua"
    local fn, err = loadfile(path)
    if not fn then
        error("Could not load display module [" .. name .. "]: " .. tostring(err), 0)
    end
    return fn()
end

local client = dofile("client.lua")
local controlCfg = dofile("control_config.lua")
local core = loadDisplay("core")
local device = loadDisplay("device")
local airspeed = loadDisplay("airspeed")

local function optionalNumber(index, name, default)
    if args[index] == nil then
        return default, true
    end

    local value = tonumber(args[index])
    if value == nil then
        print("ERROR: Invalid " .. name .. ".")
        return nil, false
    end

    return value, true
end

if not args[1] then
    print("Usage: monitor_airspeed.lua <displaySide> [period] [textScale]")
    print("Example: monitor_airspeed.lua left 0.5 1")
    return
end

local side = args[1]
local period, ok = optionalNumber(2, "period", 0.5)
if not ok then return end

local textScale
textScale, ok = optionalNumber(3, "text scale", 1)
if not ok then return end

if period <= 0 then
    print("ERROR: Invalid period.")
    return
end
if textScale <= 0 then
    print("ERROR: Invalid text scale.")
    return
end
if type(sleep) ~= "function" then
    print("ERROR: sleep() is not available in this runtime.")
    return
end

local screen, screenErr = device.wrap(side)
if not screen then
    print("ERROR: " .. tostring(screenErr))
    return
end

core.configure(screen, textScale)

local cfg = client.config()
local targetID = cfg.nodes and cfg.nodes.Airspeed
local status = "ID " .. tostring(targetID) .. "  " .. tostring(period) .. "s"

local function buildMetricState(data)
    local forwardTarget = controlCfg.forwardSpeed and controlCfg.forwardSpeed.setpoint

    return {
        metrics = {
            {
                key = "speed",
                label = "Speed",
                source = "forward",
                current = data and data.forward or nil,
                currentErr = data and data.forwardErr or nil,
                target = forwardTarget
            },
            {
                key = "vertical",
                label = "Vertical",
                source = "down",
                current = data and data.down or nil,
                currentErr = data and data.downErr or nil,
                target = nil
            }
        }
    }
end

while true do
    local data, err = client.readAirspeed()
    if data then
        airspeed.draw(screen, buildMetricState(data), status)
    else
        airspeed.drawError(screen, err or "No data", status)
    end

    sleep(period)
end
