local cfg = dofile("config.lua")
local rpc = dofile("rpc.lua")
local airspeed = dofile("airspeed.lua")

rednet.open(cfg.modemSide)

print("Airspeed node online")
print("ID: " .. os.getComputerID())

for _, name in ipairs(airspeed.sensorNames(cfg)) do
    print(name .. " = " .. tostring(cfg.sensors[name].side))
end

while true do
    local sender, msg = rednet.receive(cfg.protocol)

    if type(msg) == "table" and msg.method == "readAll" then
        rpc.reply(sender, cfg.protocol, true, airspeed.readAll(cfg))
    elseif type(msg) == "table" and msg.method ~= "get" then
        rpc.reply(sender, cfg.protocol, false, "Unsupported method: " .. tostring(msg.method))
    else
        local sensorName, targetErr = airspeed.resolveTarget(cfg, msg)

        if sensorName then
            local value, err = airspeed.read(cfg, sensorName)
            rpc.reply(sender, cfg.protocol, value ~= nil, value or err)
        else
            rpc.reply(sender, cfg.protocol, false, targetErr)
        end
    end
end
