local M = {}

function M.getSensor(side)
    local sensor = peripheral.wrap(side)
    if not sensor then
        return nil, "No sensor on " .. tostring(side)
    end
    if type(sensor.getVelocity) ~= "function" then
        return nil, "Device on " .. tostring(side) .. " has no getVelocity"
    end
    return sensor
end

function M.readAxis(sensor, axisName, index)
    local v = sensor.getVelocity()

    if type(v) == "number" then
        return v
    end

    if type(v) == "table" then
        return v[axisName] or v[index] or 0
    end

    return 0
end

function M.resolveTarget(cfg, msg)
    local target = msg
    if type(msg) == "table" then
        target = msg.target
    end

    for name, spec in pairs(cfg.sensors or {}) do
        if target == name or target == spec.side then
            return name
        end

        for _, alias in ipairs(spec.aliases or {}) do
            if target == alias then
                return name
            end
        end
    end

    return nil, "Unknown target [" .. tostring(target) .. "]"
end

function M.read(cfg, sensorName)
    local spec = cfg.sensors and cfg.sensors[sensorName]
    if not spec then
        return nil, "Unknown sensor [" .. tostring(sensorName) .. "]"
    end

    local sensor, err = M.getSensor(spec.side)
    if not sensor then
        return nil, err
    end

    return M.readAxis(sensor, spec.axis, spec.index)
end

return M
