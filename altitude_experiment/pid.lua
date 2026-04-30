local M = {}

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

function M.new(cfg)
    cfg = cfg or {}

    return {
        kp = tonumber(cfg.kp) or 0,
        ki = tonumber(cfg.ki) or 0,
        kd = tonumber(cfg.kd) or 0,
        bias = tonumber(cfg.bias) or 0,
        outputMin = tonumber(cfg.outputMin),
        outputMax = tonumber(cfg.outputMax),
        integralMin = tonumber(cfg.integralMin),
        integralMax = tonumber(cfg.integralMax),
        integralZone = tonumber(cfg.integralZone),
        integralLeak = tonumber(cfg.integralLeak),
        resetIntegralOnErrorSignChange = cfg.resetIntegralOnErrorSignChange == true,
        integral = 0,
        previousError = nil,
        previousIntegralError = nil
    }
end

function M.reset(state)
    state.integral = 0
    state.previousError = nil
    state.previousIntegralError = nil
end

function M.update(state, setpoint, measurement, dt, derivative)
    if type(state) ~= "table" then
        return nil, "Missing PID state"
    end

    local elapsed = tonumber(dt)
    if elapsed == nil or elapsed <= 0 then
        return nil, "Invalid dt"
    end

    local target = tonumber(setpoint)
    local current = tonumber(measurement)
    if target == nil then
        return nil, "Invalid setpoint"
    end
    if current == nil then
        return nil, "Invalid measurement"
    end

    local errorValue = target - current
    local shouldIntegrate = true
    if state.integralZone ~= nil and math.abs(errorValue) > state.integralZone then
        shouldIntegrate = false
    end
    if state.resetIntegralOnErrorSignChange and
        state.previousIntegralError ~= nil and
        errorValue * state.previousIntegralError < 0 then
        state.integral = 0
    end
    if shouldIntegrate then
        state.integral = clamp(
            state.integral + errorValue * elapsed,
            state.integralMin,
            state.integralMax
        )
    else
        local leak = state.integralLeak
        if leak ~= nil and leak >= 0 and leak <= 1 then
            state.integral = state.integral * leak
        end
    end
    state.previousIntegralError = errorValue

    local derivativeValue = tonumber(derivative)
    if derivativeValue == nil then
        derivativeValue = 0
        if state.previousError ~= nil then
            derivativeValue = (errorValue - state.previousError) / elapsed
        end
    end
    state.previousError = errorValue

    local output =
        state.bias +
        state.kp * errorValue +
        state.ki * state.integral +
        state.kd * derivativeValue

    output = clamp(output, state.outputMin, state.outputMax)

    return output, {
        error = errorValue,
        integral = state.integral,
        derivative = derivativeValue
    }
end

return M
