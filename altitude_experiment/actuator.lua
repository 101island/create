local M = {}

local states = {}
local PWM_EPSILON = 1.0e-9

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

local function nowSeconds()
    if type(os) == "table" and type(os.epoch) == "function" then
        return os.epoch("utc") / 1000
    end
    if type(os) == "table" and type(os.clock) == "function" then
        return os.clock()
    end
    return 0
end

local function pwmPeriod(spec, cfg)
    local global = cfg and cfg.actuatorPwm or {}
    return tonumber(spec.pwmPeriod) or tonumber(global.period) or 0.05
end

local function pwmEnabled(spec, cfg)
    local global = cfg and cfg.actuatorPwm or {}
    if spec.pwmEnabled ~= nil then
        return spec.pwmEnabled ~= false
    end
    return global.enabled ~= false
end

local function stateKey(alias)
    return tostring(alias)
end

local function getState(alias)
    local key = stateKey(alias)
    local state = states[key]
    if not state then
        state = {
            target = 0,
            exactOutput = 0,
            lower = 0,
            upper = 0,
            fraction = 0,
            accumulator = 0,
            currentOutput = 0,
            lastUpdate = 0,
            initialized = false
        }
        states[key] = state
    end
    return state
end

local function computeOutput(state)
    if state.lower == state.upper or state.fraction <= 0 then
        state.accumulator = 0
        return state.lower
    end

    if state.fraction >= 1 then
        state.accumulator = 0
        return state.upper
    end

    state.accumulator = state.accumulator + state.fraction
    if state.accumulator + PWM_EPSILON >= 1 then
        state.accumulator = state.accumulator - 1
        if math.abs(state.accumulator) < PWM_EPSILON then
            state.accumulator = 0
        end
        return state.upper
    end
    return state.lower
end

local function applyExactTarget(state, exactOutput)
    local lower = math.floor(exactOutput)
    local upper = math.ceil(exactOutput)
    state.exactOutput = exactOutput
    state.lower = lower
    state.upper = upper
    state.fraction = exactOutput - lower
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
    local level = clamp(value * scale + bias, outputMin, outputMax)
    local state = getState(alias)

    state.target = value
    state.address = address
    state.outputSide = spec.outputSide or "left"
    state.method = pwmEnabled(spec, cfg) and "pwm_pdm" or "setAnalogOutput"
    applyExactTarget(state, level)

    if not pwmEnabled(spec, cfg) then
        state.currentOutput = math.floor(level + 0.5)
        device.setAnalogOutput(state.outputSide, state.currentOutput)
        state.lastUpdate = nowSeconds()
        state.initialized = true
    elseif not state.initialized then
        M.update(cfg, alias, true)
    end

    return {
        alias = alias,
        address = address,
        command = value,
        output = state.currentOutput,
        exactOutput = level,
        targetOutput = level,
        lowerOutput = state.lower,
        upperOutput = state.upper,
        pwmFraction = state.fraction,
        pwmPeriod = pwmPeriod(spec, cfg),
        method = state.method
    }
end

function M.update(cfg, alias, force)
    local state = getState(alias)
    local device, err, address, spec = M.wrap(cfg, alias)
    if not device then
        return nil, err
    end
    if type(device.setAnalogOutput) ~= "function" then
        return nil, "[" .. alias .. "] does not support setAnalogOutput"
    end

    local period = pwmPeriod(spec, cfg)
    local currentTime = nowSeconds()
    if not force and state.initialized and currentTime - state.lastUpdate < period then
        return {
            alias = alias,
            address = address,
            output = state.currentOutput,
            exactOutput = state.exactOutput,
            targetOutput = state.exactOutput,
            method = state.method or "pwm_pdm",
            skipped = true
        }
    end

    local enabled = pwmEnabled(spec, cfg)
    local output
    if enabled then
        output = computeOutput(state)
    else
        output = math.floor(state.exactOutput + 0.5)
        state.accumulator = 0
    end

    state.currentOutput = output
    state.lastUpdate = currentTime
    state.initialized = true
    state.address = address
    state.outputSide = spec.outputSide or "left"
    state.method = enabled and "pwm_pdm" or "setAnalogOutput"
    device.setAnalogOutput(state.outputSide, output)

    return {
        alias = alias,
        address = address,
        output = output,
        exactOutput = state.exactOutput,
        targetOutput = state.exactOutput,
        lowerOutput = state.lower,
        upperOutput = state.upper,
        pwmFraction = state.fraction,
        pwmAccumulator = state.accumulator,
        pwmPeriod = period,
        method = state.method
    }
end

function M.updateAll(cfg, force)
    local result = {
        order = M.componentNames(cfg)
    }

    for _, alias in ipairs(result.order) do
        local value, err = M.update(cfg, alias, force)
        if value then
            result[alias] = value.output
            result[alias .. "ExactOutput"] = value.exactOutput
            result[alias .. "TargetOutput"] = value.targetOutput
            result[alias .. "Method"] = value.method
        else
            result[alias] = nil
            result[alias .. "Err"] = err
        end
    end

    return result
end

function M.runPwm(cfg, options)
    options = options or {}
    local period = tonumber(options.period)
    if period == nil then
        local global = cfg and cfg.actuatorPwm or {}
        period = tonumber(global.period) or 0.05
    end
    if period <= 0 then
        period = 0.05
    end

    while true do
        M.updateAll(cfg)
        sleep(period)
    end
end

function M.read(cfg, alias)
    local device, err, address, spec = M.wrap(cfg, alias)
    if not device then
        return nil, err
    end

    if type(device.getAnalogueOutput) ~= "function" then
        return nil, "[" .. alias .. "] does not support getAnalogueOutput"
    end

    local outputSide = spec.outputSide or "left"
    local value = device.getAnalogueOutput(outputSide)
    local state = getState(alias)
    return {
        alias = alias,
        address = address,
        output = value,
        exactOutput = state.exactOutput,
        targetOutput = state.exactOutput,
        command = state.target,
        method = state.method or "getAnalogueOutput",
        pwmFraction = state.fraction,
        pwmAccumulator = state.accumulator,
        pwmPeriod = pwmPeriod(spec, cfg)
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
            result[name .. "ExactOutput"] = value.exactOutput
            result[name .. "TargetOutput"] = value.targetOutput
            result[name .. "Command"] = value.command
            result[name .. "PwmFraction"] = value.pwmFraction
            result[name .. "PwmAccumulator"] = value.pwmAccumulator
            result[name .. "Method"] = value.method
        else
            result[name] = nil
            result[name .. "Err"] = err
        end
    end

    return result
end

return M
