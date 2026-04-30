local args = {...}
local runtimeState = dofile("runtime_state.lua")
local dashboard = dofile("display_dashboard.lua")
local dataLogger = dofile("data_logger.lua")
local actuator = dofile("actuator.lua")

local values = {}
local dryRun = false
local noDisplay = false
local logEnabled = nil
local logPath = nil

local index = 1
while index <= #args do
    local arg = args[index]
    if arg == "--dry-run" then
        dryRun = true
    elseif arg == "--no-display" then
        noDisplay = true
    elseif arg == "--log" then
        logEnabled = true
        if args[index + 1] and args[index + 1]:sub(1, 2) ~= "--" and tonumber(args[index + 1]) == nil then
            logPath = args[index + 1]
            index = index + 1
        end
    else
        values[#values + 1] = arg
    end
    index = index + 1
end

local function optionalNumber(index, name)
    if values[index] == nil then
        return nil, true
    end

    local value = tonumber(values[index])
    if value == nil then
        print("ERROR: Invalid " .. name .. ".")
        return nil, false
    end

    return value, true
end

local positionSetpoint, ok = optionalNumber(1, "position setpoint")
if not ok then return end

local outerKp
outerKp, ok = optionalNumber(2, "outer kp")
if not ok then return end

local innerKp
innerKp, ok = optionalNumber(3, "inner kp")
if not ok then return end

local period
period, ok = optionalNumber(4, "period")
if not ok then return end

local runtime = runtimeState.new({
    dryRun = dryRun,
    positionSetpoint = positionSetpoint,
    outerKp = outerKp,
    innerKp = innerKp,
    period = period
})

local logger = dataLogger.new(runtime.config.logging or {}, {
    enabled = logEnabled,
    path = logPath
})

if period ~= nil and period <= 0 then
    print("ERROR: Invalid period.")
    return
end

local function printHeader()
    print("Altitude experiment")
    print("mode: " .. tostring(runtime.mode))
    print("enabled: " .. tostring(runtime.enabled))
    print("period: " .. tostring(runtime.period))
    print("dryRun: " .. tostring(runtime.dryRun))
    print("altitude target: " .. tostring(runtime.setpoints.altitude))
    print("speed target: " .. tostring(runtime.setpoints.speed))
    print("outer PID: kp=" .. tostring(runtime.outerPid.kp) .. " ki=" .. tostring(runtime.outerPid.ki) .. " kd=" .. tostring(runtime.outerPid.kd))
    print("inner PID correction: kp=" .. tostring(runtime.innerPid.kp) .. " ki=" .. tostring(runtime.innerPid.ki) .. " kd=" .. tostring(runtime.innerPid.kd) .. " bias=" .. tostring(runtime.innerPid.bias))
    print("correction range: " .. tostring(runtime.innerPid.outputMin) .. ".." .. tostring(runtime.innerPid.outputMax))
    print("actuator range: " .. tostring(runtime.feedforward.outputMin) .. ".." .. tostring(runtime.feedforward.outputMax))
    print("logging: " .. tostring(logger.enabled) .. " " .. tostring(logger.path) .. (logger.err and (" ERR=" .. tostring(logger.err)) or ""))
    print("Use monitor touch or keyboard: left/right page, up/down field, -/+, space enable, m mode, r reset.")
end

local function controlLoop()
    printHeader()
    local lastLogErr = nil

    while true do
        runtimeState.step(runtime, { applyOutput = true })
        local logOk, logErr = dataLogger.write(logger, runtime)
        if not logOk and logErr ~= lastLogErr then
            print("LOG ERROR: " .. tostring(logErr))
            lastLogErr = logErr
        end
        print(runtimeState.summary(runtime))
        sleep(runtime.period)
    end
end

local function displayLoop()
    if noDisplay then
        while true do
            sleep(3600)
        end
    end

    local ok, err = pcall(dashboard.run, runtime, {
        sample = false
    })
    if not ok then
        print("DISPLAY ERROR: " .. tostring(err))
    end

    while true do
        sleep(3600)
    end
end

local function pwmLoop()
    if dryRun then
        while true do
            sleep(3600)
        end
    end

    actuator.runPwm(runtime.hardware)
end

if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
    parallel.waitForAny(controlLoop, displayLoop, pwmLoop)
else
    print("WARN: parallel.waitForAny is unavailable; fractional actuator PWM will not refresh independently.")
    controlLoop()
end
