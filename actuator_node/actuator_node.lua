local cfg = dofile("config.lua")
local rpc = dofile("rpc.lua")
local actuator = dofile("actuator.lua")

rednet.open(cfg.modemSide)

print("Actuator node online")
print("ID: " .. os.getComputerID())
print("Modem: " .. cfg.modemSide)

while true do
    local sender, msg = rednet.receive(cfg.protocol)

    if type(msg) == "table" and msg.target and msg.method then
        if msg.method == "setSpeed" then
            local rpm = msg.args and msg.args[1]
            local result, err = actuator.setSpeed(cfg, msg.target, rpm)

            if result then
                rpc.reply(sender, cfg.protocol, true, result.rpm)
                print("OK: " .. msg.target .. " = " .. result.rpm .. " RPM")
            else
                rpc.reply(sender, cfg.protocol, false, err)
                print("ERR: " .. tostring(err))
            end

        elseif msg.method == "readAll" then
            local result = actuator.readAll(cfg)
            rpc.reply(sender, cfg.protocol, true, result)

        elseif msg.method == "stop" then
            local result, err = actuator.stop(cfg, msg.target)

            if result then
                rpc.reply(sender, cfg.protocol, true, 0)
                print("OK: " .. msg.target .. " stopped")
            else
                rpc.reply(sender, cfg.protocol, false, err)
                print("ERR: " .. tostring(err))
            end

        else
            rpc.reply(sender, cfg.protocol, false, "Unsupported method: " .. tostring(msg.method))
        end
    end
end
