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
        integral = 0,
        previousError = nil
    }
end

function M.reset(state)
    state.integral = 0
    state.previousError = nil
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
    state.integral = clamp(
        state.integral + errorValue * elapsed,
        state.integralMin,
        state.integralMax
    )

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
