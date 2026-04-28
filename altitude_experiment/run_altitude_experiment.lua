local args = {...}
local runtimeState = dofile("runtime_state.lua")
local dashboard = dofile("display_dashboard.lua")

local values = {}
local dryRun = false
local noDisplay = false

for _, arg in ipairs(args) do
    if arg == "--dry-run" then
        dryRun = true
    elseif arg == "--no-display" then
        noDisplay = true
    else
        values[#values + 1] = arg
    end
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
    print("Use monitor touch or keyboard: left/right page, up/down field, -/+, space enable, m mode, r reset.")
end

local function controlLoop()
    printHeader()

    while true do
        runtimeState.step(runtime, { applyOutput = true })
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

if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
    parallel.waitForAny(controlLoop, displayLoop)
else
    print("WARN: parallel.waitForAny is unavailable; running control loop only.")
    controlLoop()
end
