local client = dofile("client.lua")
local cfg = client.config()

local gnssID = cfg.nodes and cfg.nodes.GNSS

print("Target ID: " .. tostring(gnssID))
print("Protocol: " .. tostring(cfg.protocol))
print("Modem: " .. tostring(cfg.modemSide))

local result, err = client.readGnss()
if not result then
    print("ERROR: " .. tostring(err))
    return
end

local order = result.order or {}
if #order == 0 then
    for name in pairs(result) do
        if name ~= "nodeID" and name ~= "order" and not name:find("Err$") then
            order[#order + 1] = name
        end
    end
    table.sort(order)
end

for _, name in ipairs(order) do
    print(name .. ": " .. tostring(result[name]))
end
