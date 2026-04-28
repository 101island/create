local M = {}
local pwmCounters = {}

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

local function quantize(alias, value, window)
    local lower = math.floor(value)
    local upper = math.ceil(value)

    if lower == upper or window <= 1 then
        return math.floor(value + 0.5)
    end

    local fraction = value - lower
    local upperTicks = math.floor(fraction * window + 0.5)
    local counter = (pwmCounters[alias] or 0) % window
    pwmCounters[alias] = (counter + 1) % window

    if counter < upperTicks then
        return upper
    end
    return lower
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
    local spec = cfg.components and cfg.components[alias]
    if type(spec) ~= "table" then
        return nil, "Unknown alias [" .. tostring(alias) .. "]"
    end
    if type(peripheral) ~= "table" or type(peripheral.find) ~= "function" then
        return nil, "peripheral.find() is not available in this runtime"
    end

    local peripheralType = spec.peripheralType or "redstone_relay"
    local device = peripheral.find(peripheralType)
    if not device then
        return nil, "Could not find peripheral type [" .. tostring(peripheralType) .. "]"
    end

    return device, nil, peripheralType, spec
end

function M.setOutput(cfg, alias, command)
    local value = tonumber(command)
    if value == nil then
        return nil, "Invalid output"
    end

    local device, err, address, spec = M.wrap(cfg, alias)
    if not device then
        return nil, err
    end

    if type(device.setAnalogOutput) ~= "function" then
        return nil, "[" .. alias .. "] does not support setAnalogOutput"
    end

    local scale = tonumber(spec.scale) or 1
    local bias = tonumber(spec.bias) or 0
    local outputMin = tonumber(spec.outputMin) or 0
    local outputMax = tonumber(spec.outputMax) or 15
    local outputSide = spec.outputSide or "left"
    local pwmWindow = tonumber(spec.pwmWindow) or 1
    local level = clamp(value * scale + bias, outputMin, outputMax)
    local quantizedLevel = quantize(alias, level, pwmWindow)
    device.setAnalogOutput(outputSide, quantizedLevel)

    return {
        alias = alias,
        address = address,
        command = value,
        output = quantizedLevel,
        exactOutput = level,
        method = "setAnalogOutput"
    }
end

function M.read(cfg, alias)
    local device, err, address = M.wrap(cfg, alias)
    if not device then
        return nil, err
    end

    if type(device.getAnalogueOutput) ~= "function" then
        return nil, "[" .. alias .. "] does not support getAnalogueOutput"
    end

    local spec = cfg.components and cfg.components[alias] or {}
    local outputSide = spec.outputSide or "left"
    local value = device.getAnalogueOutput(outputSide)
    return {
        alias = alias,
        address = address,
        output = value,
        method = "getAnalogueOutput"
    }
end

function M.readAll(cfg)
    local result = {
        order = M.componentNames(cfg)
    }

    for _, name in ipairs(result.order) do
        local value, err = M.read(cfg, name)
        if value then
            result[name] = value.output
            result[name .. "Method"] = value.method
        else
            result[name] = nil
            result[name .. "Err"] = err
        end
    end

    return result
end

return M
