local args = {...}
local client = dofile("client.lua")

if #args < 3 then
    print("Usage: send_actuator.lua <nodeID> <alias> <rpm>")
    print("Example: send_actuator.lua 3 MainThruster 100")
    return
end

local nodeID = tonumber(args[1])
local alias = args[2]
local rpm = tonumber(args[3])

if not nodeID then
    print("ERROR: Invalid node ID.")
    return
end

if rpm == nil then
    print("ERROR: Invalid RPM.")
    return
end

local value, err = client.setSpeed(nodeID, alias, rpm)

if value == nil then
    print("ERROR: " .. tostring(err))
else
    print("OK: " .. alias .. " = " .. tostring(value) .. " RPM")
end
