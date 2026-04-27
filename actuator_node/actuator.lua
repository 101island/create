local M = {}

function M.loadConfig(path)
    local ok, cfg = pcall(dofile, path or "config.lua")
    if not ok then
        return nil, tostring(cfg)
    end
    if type(cfg.components) ~= "table" then
        return nil, "config.components is missing or invalid"
    end
    return cfg
end

function M.wrap(cfg, alias)
    local address = cfg.components[alias]
    if not address then
        return nil, "Unknown alias [" .. tostring(alias) .. "]"
    end

    local device = peripheral.wrap(address)
    if not device then
        return nil, "Could not find [" .. alias .. "] at [" .. address .. "]"
    end

    return device, nil, address
end

function M.setSpeed(cfg, alias, rpm)
    local value = tonumber(rpm)
    if value == nil then
        return nil, "Invalid RPM"
    end

    local device, err, address = M.wrap(cfg, alias)
    if not device then
        return nil, err
    end

    if type(device.setSpeed) ~= "function" then
        return nil, "[" .. alias .. "] does not support setSpeed"
    end

    local safeRPM = math.max(-256, math.min(256, value))
    device.setSpeed(safeRPM)

    return {
        alias = alias,
        address = address,
        rpm = safeRPM
    }
end

function M.stop(cfg, alias)
    local device, err, address = M.wrap(cfg, alias)
    if not device then
        return nil, err
    end

    if type(device.stop) == "function" then
        device.stop()
    elseif type(device.setSpeed) == "function" then
        device.setSpeed(0)
    else
        return nil, "[" .. alias .. "] does not support stop or setSpeed"
    end

    return {
        alias = alias,
        address = address,
        rpm = 0
    }
end

return M
