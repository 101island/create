local M = {}

function M.getSensor(side)
    local sensor = peripheral.wrap(side)
    if not sensor then
        return nil, "No sensor on " .. tostring(side)
    end
    if type(sensor.getHeight) ~= "function" then
        return nil, "Device on " .. tostring(side) .. " has no getHeight"
    end
    return sensor
end

function M.read(cfg)
    local spec = cfg and cfg.altitude
    if type(spec) ~= "table" then
        return nil, "Missing altitude config"
    end

    local sensor, err = M.getSensor(spec.side)
    if not sensor then
        return nil, err
    end

    local value = sensor.getHeight()
    local scale = tonumber(spec.scale) or 1
    local bias = tonumber(spec.bias) or 0
    return value * scale + bias
end

return M
