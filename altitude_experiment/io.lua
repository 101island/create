local verticalSpeed = dofile("vertical_speed.lua")
local altitude = dofile("altitude.lua")
local actuator = dofile("actuator.lua")

local M = {}

local function mergeOrder(...)
    local order = {}
    local seen = {}

    for _, source in ipairs({ ... }) do
        if type(source) == "table" and type(source.order) == "table" then
            for _, name in ipairs(source.order) do
                if not seen[name] then
                    seen[name] = true
                    order[#order + 1] = name
                end
            end
        end
    end

    return order
end

function M.readSensors(cfg)
    local sensorCfg = cfg or {}
    local altitudeValue, altitudeErr = altitude.read(sensorCfg)
    local speedData = verticalSpeed.readAll(sensorCfg, altitudeValue, altitudeErr)

    local result = speedData or { order = {} }
    result.order = mergeOrder(speedData)
    result.altitude = altitudeValue
    if altitudeErr then
        result.altitudeErr = altitudeErr
    end

    return result
end

function M.readActuators(cfg)
    return actuator.readAll(cfg or {})
end

function M.readAll(cfg)
    return {
        sensors = M.readSensors(cfg),
        actuators = M.readActuators(cfg)
    }
end

return M
