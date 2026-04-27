local args = {...}
local client = dofile("client.lua")
local pid = dofile("pid.lua")
local controlCfg = dofile("control_config.lua")

local cfg = controlCfg.forwardSpeed
if type(cfg) ~= "table" then
    print("ERROR: Missing forwardSpeed config.")
    return
end

local outputCfg = cfg.output or {}
local pidCfg = cfg.pid or {}

local values = {}
local dryRun = false
for _, arg in ipairs(args) do
    if arg == "--dry-run" then
        dryRun = true
    else
        values[#values + 1] = arg
    end
end

local function optionalNumber(index, name, default)
    if values[index] == nil then
        return default, true
    end

    local value = tonumber(values[index])
    if value == nil then
        print("ERROR: Invalid " .. name .. ".")
        return nil, false
    end

    return value, true
end

local setpoint, ok = optionalNumber(1, "setpoint", cfg.setpoint)
if not ok then return end

local kp
kp, ok = optionalNumber(2, "kp", pidCfg.kp)
if not ok then return end

local ki
ki, ok = optionalNumber(3, "ki", pidCfg.ki or 0)
if not ok then return end

local kd
kd, ok = optionalNumber(4, "kd", pidCfg.kd or 0)
if not ok then return end

local period
period, ok = optionalNumber(5, "period", cfg.period or 0.2)
if not ok then return end

if setpoint == nil then
    print("ERROR: Missing setpoint. Set forwardSpeed.setpoint or pass it on the command line.")
    return
end
if kp == nil then
    print("ERROR: Missing kp. Set forwardSpeed.pid.kp or pass it on the command line.")
    return
end
if period == nil or period <= 0 then
    print("ERROR: Invalid period.")
    return
end
if type(outputCfg.node) ~= "string" or outputCfg.node == "" then
    print("ERROR: Missing output node.")
    return
end
if type(outputCfg.alias) ~= "string" or outputCfg.alias == "" then
    print("ERROR: Missing output alias.")
    return
end
if type(sleep) ~= "function" then
    print("ERROR: sleep() is not available in this runtime.")
    return
end

if #values == 0 then
    print("Using control_config.lua defaults")
elseif #values < 2 then
    print("Usage: run_forward_speed.lua [setpoint] [kp] [ki] [kd] [period] [--dry-run]")
    print("Example: run_forward_speed.lua 20 1.5 0 0.1 0.2 --dry-run")
    print("You can also set forwardSpeed.setpoint and forwardSpeed.pid.kp in control_config.lua and run with no numeric arguments.")
end

local controller = pid.new({
    kp = kp,
    ki = ki,
    kd = kd,
    bias = pidCfg.bias,
    outputMin = pidCfg.outputMin,
    outputMax = pidCfg.outputMax,
    integralMin = pidCfg.integralMin,
    integralMax = pidCfg.integralMax
})

local lastOutput = nil

local function limitStep(value)
    local maxStep = tonumber(outputCfg.maxStep)
    if not maxStep or not lastOutput then
        return value
    end

    local delta = value - lastOutput
    if delta > maxStep then
        return lastOutput + maxStep
    end
    if delta < -maxStep then
        return lastOutput - maxStep
    end
    return value
end

local function setOutput(rpm)
    lastOutput = rpm

    if dryRun then
        return rpm
    end

    return client.setNodeSpeed(outputCfg.node, outputCfg.alias, rpm)
end

print("Forward speed loop")
print("Target: " .. tostring(setpoint))
print("PID: kp=" .. tostring(kp) .. " ki=" .. tostring(ki) .. " kd=" .. tostring(kd))
print("Period: " .. tostring(period))
print("Output: " .. tostring(outputCfg.node) .. " / " .. tostring(outputCfg.alias))
print("Dry run: " .. tostring(dryRun))

while true do
    local airspeed, readErr = client.readAirspeed()

    if not airspeed or airspeed.forward == nil then
        local err = readErr or (airspeed and airspeed.forwardErr) or "No forward speed"
        print("ERROR: " .. tostring(err))

        if cfg.stopOnSensorError then
            local _, stopErr = setOutput(0)
            if stopErr then
                print("STOP ERROR: " .. tostring(stopErr))
            end
        end
    else
        local rawOutput, updateInfoOrErr = pid.update(controller, setpoint, airspeed.forward, period)
        if rawOutput == nil then
            print("ERROR: " .. tostring(updateInfoOrErr))
        else
            local rpm = limitStep(rawOutput)
            local value, err = setOutput(rpm)

            if value == nil then
                print("OUTPUT ERROR: " .. tostring(err))
            else
                print(
                    "forward=" .. tostring(airspeed.forward) ..
                    " target=" .. tostring(setpoint) ..
                    " error=" .. tostring(updateInfoOrErr.error) ..
                    " rpm=" .. tostring(value)
                )
            end
        end
    end

    sleep(period)
end
