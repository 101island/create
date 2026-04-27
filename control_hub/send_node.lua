local args = {...}
local client = dofile("client.lua")

if #args < 2 then
    print("Usage: send_node <nodeName> <rpm>")
    print("   or: send_node <nodeName> <targetAlias> <rpm>")
    print("Example: send_node RightThruster 100")
    print("Example: send_node RightThruster RightThruster 100")
    return
end

local nodeName = args[1]
local targetAlias
local rpm

if #args == 2 then
    targetAlias = nodeName
    rpm = tonumber(args[2])
else
    targetAlias = args[2]
    rpm = tonumber(args[3])
end

if rpm == nil then
    print("ERROR: Invalid RPM.")
    return
end

local value, err = client.setNodeSpeed(nodeName, targetAlias, rpm)

if value == nil then
    print("ERROR: " .. tostring(err))
else
    print("OK: " .. targetAlias .. " = " .. tostring(value) .. " RPM")
end
