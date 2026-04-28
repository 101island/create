local M = {}

local cfg = dofile("config.lua")
local actuator = dofile("actuator.lua")
local io = dofile("io.lua")

function M.config()
    return cfg
end

function M.setOutput(alias, value)
    local result, err = actuator.setOutput(cfg, alias, value)
    if not result then
        return nil, err
    end
    return result.output
end

function M.readSensors()
    return io.readSensors(cfg)
end

function M.readActuators()
    return io.readActuators(cfg)
end

function M.readIO()
    return io.readAll(cfg)
end

return M
