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

function M.readVelocity(spec)
    local sensor, err = M.getSensor(spec.side)
    if not sensor then
        return nil, err
    end

    if type(spec.remoteName) == "string" and spec.remoteName ~= "" then
        if type(sensor.callRemote) ~= "function" then
            return nil, "Device on " .. tostring(spec.side) .. " has no callRemote"
        end

        local ok, value = pcall(sensor.callRemote, spec.remoteName, "getVelocity")
        if not ok then
            return nil, tostring(value)
        end
        return value
    end

    return sensor.getVelocity()
end

function M.readAxis(v, axisName, index)
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

    if type(target) == "string" and cfg.sensors and cfg.sensors[target] then
        return target
    end

    return nil, "Unknown target [" .. tostring(target) .. "]"
end

function M.sensorNames(cfg)
    local names = {}

    if type(cfg.sensorOrder) == "table" then
        for _, name in ipairs(cfg.sensorOrder) do
            if cfg.sensors and cfg.sensors[name] then
                names[#names + 1] = name
            end
        end
        return names
    end

    for name in pairs(cfg.sensors or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function M.read(cfg, sensorName)
    local spec = cfg.sensors and cfg.sensors[sensorName]
    if not spec then
        return nil, "Unknown sensor [" .. tostring(sensorName) .. "]"
    end

    local raw, err = M.readVelocity(spec)
    if raw == nil and err then
        return nil, err
    end

    local value = M.readAxis(raw, spec.axis, spec.index)
    local scale = tonumber(spec.scale) or 1
    return value * scale
end

function M.readAll(cfg)
    local result = {
        order = M.sensorNames(cfg)
    }

    for _, name in ipairs(result.order) do
        local value, err = M.read(cfg, name)
        result[name] = value
        if err then
            result[name .. "Err"] = err
        end
    end

    return result
end

return M
