local args = {...}
local client = dofile("client.lua")

local alias = args[1]
local value = tonumber(args[2])

if type(alias) ~= "string" or alias == "" or value == nil then
    print("Usage: set_actuator.lua <alias> <output>")
    return
end

local output, err = client.setOutput(alias, value)
if output == nil then
    print("ERROR: " .. tostring(err))
    return
end

print("OK: " .. tostring(alias) .. " = " .. tostring(output))
