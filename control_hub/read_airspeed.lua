local client = dofile("client.lua")
local cfg = client.config()

local airspeedID = cfg.nodes and cfg.nodes.Airspeed

print("Target ID: " .. tostring(airspeedID))
print("Protocol: " .. tostring(cfg.protocol))
print("Modem: " .. tostring(cfg.modemSide))

local result, err = client.readAirspeed()
if not result then
    print("ERROR: " .. tostring(err))
    return
end

local function valueOrError(value, errorValue)
    if value == nil then
        return errorValue
    end
    return value
end

print("Forward: " .. tostring(valueOrError(result.forward, result.forwardErr)))
print("Vertical: " .. tostring(valueOrError(result.vertical, result.verticalErr)))
