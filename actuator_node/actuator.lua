local M = {}

local function findSpeedSetter(device)
    if type(device.setSpeed) == "function" then
        return device.setSpeed, "setSpeed"
    end
    if type(device.setGeneratedSpeed) == "function" then
        return device.setGeneratedSpeed, "setGeneratedSpeed"
    end
    return nil, nil
end

local function findSpeedGetter(device)
    if type(device.getSpeed) == "function" then
        return device.getSpeed, "getSpeed"
    end
    if type(device.getGeneratedSpeed) == "function" then
        return device.getGeneratedSpeed, "getGeneratedSpeed"
    end
    return nil, nil
end

local function clampValue(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

local function castValue(value, valueType)
    if valueType == "boolean" then
        return value ~= 0
    end
    if valueType == "integer" then
        if value >= 0 then
            return math.floor(value + 0.5)
        end
        return math.ceil(value - 0.5)
    end
    return value
end

local function applyArgsTemplate(template, value)
    local args = {}
    for _, item in ipairs(template or {}) do
        if item == "$value" then
            args[#args + 1] = value
        else
            args[#args + 1] = item
        end
    end
    return args
end

local function callRemoteMethod(device, remoteName, methodName, args)
    if type(device.callRemote) ~= "function" then
        return nil, "Device has no callRemote"
    end

    local ok, result = pcall(device.callRemote, remoteName, methodName, table.unpack(args or {}))
    if not ok then
        return nil, tostring(result)
    end
    return result
end

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

function M.componentNames(cfg)
    local names = {}
    for name in pairs(cfg.components or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function M.wrap(cfg, alias)
    local spec = cfg.components[alias]
    if type(spec) ~= "table" then
        return nil, "Unknown alias [" .. tostring(alias) .. "]"
    end

    local address = spec.side
    if type(address) ~= "string" or address == "" then
        return nil, "Missing side for [" .. tostring(alias) .. "]"
    end

    local device = peripheral.wrap(address)
    if not device then
        return nil, "Could not find [" .. alias .. "] at [" .. address .. "]"
    end

    return device, nil, address, spec
end

function M.setSpeed(cfg, alias, rpm)
    local value = tonumber(rpm)
    if value == nil then
        return nil, "Invalid RPM"
    end

    local device, err, address, spec = M.wrap(cfg, alias)
    if not device then
        return nil, err
    end

    local setter, setterName = findSpeedSetter(device)
    if not setter then
        return nil, "[" .. alias .. "] does not support setSpeed or setGeneratedSpeed"
    end

    local scale = tonumber(spec.scale) or 1
    local safeRPM = math.max(-256, math.min(256, value * scale))
    setter(safeRPM)

    return {
        alias = alias,
        address = address,
        rpm = safeRPM,
        method = setterName
    }
end

function M.stop(cfg, alias)
    local device, err, address = M.wrap(cfg, alias)
    if not device then
        return nil, err
    end

    local setter = findSpeedSetter(device)

    if type(device.stop) == "function" then
        device.stop()
    elseif setter then
        setter(0)
    else
        return nil, "[" .. alias .. "] does not support stop, setSpeed, or setGeneratedSpeed"
    end

    return {
        alias = alias,
        address = address,
        rpm = 0
    }
end

function M.read(cfg, alias)
    local device, err, address = M.wrap(cfg, alias)
    if not device then
        return nil, err
    end

    local getter, getterName = findSpeedGetter(device)
    if not getter then
        return nil, "[" .. alias .. "] does not support getSpeed or getGeneratedSpeed"
    end

    local value = getter()
    return {
        alias = alias,
        address = address,
        rpm = value,
        method = getterName
    }
end

function M.readAll(cfg)
    local result = {
        order = M.componentNames(cfg)
    }

    for _, name in ipairs(result.order) do
        local value, err = M.read(cfg, name)
        if value then
            result[name] = value.rpm
            result[name .. "Method"] = value.method
        else
            result[name] = nil
            result[name .. "Err"] = err
        end
    end

    return result
end

return M
