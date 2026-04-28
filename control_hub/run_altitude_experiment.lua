local args = {...}
local client = dofile("client.lua")
local pid = dofile("pid.lua")
local controlCfg = dofile("control_config.lua")

local cfg = controlCfg.altitudeExperiment
if type(cfg) ~= "table" or cfg.enabled == false then
    print("ERROR: Missing altitudeExperiment config.")
    return
end

local outputsCfg = cfg.outputs or {}
local outerPidCfg = cfg.outerPid or {}
local innerPidCfg = cfg.innerPid or {}

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

local positionSetpoint, ok = optionalNumber(1, "position setpoint", cfg.positionSetpoint)
if not ok then return end

local outerKp
outerKp, ok = optionalNumber(2, "outer kp", outerPidCfg.kp)
if not ok then return end

local innerKp
innerKp, ok = optionalNumber(3, "inner kp", innerPidCfg.kp)
if not ok then return end

local period
period, ok = optionalNumber(4, "period", cfg.period or 0.2)
if not ok then return end

if positionSetpoint == nil then
    print("ERROR: Missing position setpoint.")
    return
end
if outerKp == nil then
    print("ERROR: Missing outer kp.")
    return
end
if innerKp == nil then
    print("ERROR: Missing inner kp.")
    return
end
if period == nil or period <= 0 then
    print("ERROR: Invalid period.")
    return
end
if type(outputsCfg) ~= "table" or #outputsCfg == 0 then
    print("ERROR: Missing altitudeExperiment.outputs config.")
    return
end
if type(sleep) ~= "function" then
    print("ERROR: sleep() is not available in this runtime.")
    return
end

local function validateMeasurement(name, spec)
    if type(spec) ~= "table" then
        print("ERROR: Missing " .. name .. " measurement config.")
        return false
    end
    if type(spec.field) ~= "string" or spec.field == "" then
        print("ERROR: Missing " .. name .. " measurement field.")
        return false
    end
    return true
end

if not validateMeasurement("position", cfg.positionMeasurement) then
    return
end
if not validateMeasurement("speed", cfg.speedMeasurement) then
    return
end

for index, item in ipairs(outputsCfg) do
    if type(item) ~= "table" then
        print("ERROR: Invalid output entry #" .. tostring(index) .. ".")
        return
    end
    if type(item.node) ~= "string" or item.node == "" then
        print("ERROR: Missing output node in entry #" .. tostring(index) .. ".")
        return
    end
    if type(item.alias) ~= "string" or item.alias == "" then
        print("ERROR: Missing output alias in entry #" .. tostring(index) .. ".")
        return
    end
    if tonumber(item.ratio) == nil then
        print("ERROR: Missing output ratio in entry #" .. tostring(index) .. ".")
        return
    end
end

if #values == 0 then
    print("Using control_config.lua defaults")
elseif #values < 3 then
    print("Usage: run_altitude_experiment.lua [positionSetpoint] [outerKp] [innerKp] [period] [--dry-run]")
    print("Example: run_altitude_experiment.lua 100 1.0 0.8 0.2 --dry-run")
end

local outerPid = pid.new({
    kp = outerKp,
    ki = outerPidCfg.ki,
    kd = outerPidCfg.kd,
    bias = outerPidCfg.bias,
    outputMin = outerPidCfg.outputMin,
    outputMax = outerPidCfg.outputMax,
    integralMin = outerPidCfg.integralMin,
    integralMax = outerPidCfg.integralMax
})

local innerPid = pid.new({
    kp = innerKp,
    ki = innerPidCfg.ki,
    kd = innerPidCfg.kd,
    bias = innerPidCfg.bias,
    outputMin = innerPidCfg.outputMin,
    outputMax = innerPidCfg.outputMax,
    integralMin = innerPidCfg.integralMin,
    integralMax = innerPidCfg.integralMax
})

local lastBaseOutput = nil

local function limitStep(value)
    local maxStep = tonumber(cfg.maxStep)
    if not maxStep or not lastBaseOutput then
        return value
    end

    local delta = value - lastBaseOutput
    if delta > maxStep then
        return lastBaseOutput + maxStep
    end
    if delta < -maxStep then
        return lastBaseOutput - maxStep
    end
    return value
end

local function buildCommands(baseRPM)
    local commands = {}

    for _, item in ipairs(outputsCfg) do
        commands[#commands + 1] = {
            node = item.node,
            alias = item.alias,
            ratio = tonumber(item.ratio) or 0,
            rpm = baseRPM * (tonumber(item.ratio) or 0)
        }
    end

    return commands
end

local function describeCommands(commands)
    local parts = {}
    for _, item in ipairs(commands) do
        parts[#parts + 1] = item.alias .. "=" .. tostring(item.rpm)
    end
    return table.concat(parts, "  ")
end

local function setOutputs(baseRPM)
    lastBaseOutput = baseRPM
    local commands = buildCommands(baseRPM)

    if dryRun then
        return {
            baseRPM = baseRPM,
            commands = commands
        }
    end

    for _, item in ipairs(commands) do
        local value, err = client.setNodeSpeed(item.node, item.alias, item.rpm)
        if value == nil then
            return nil, item.alias .. ": " .. tostring(err)
        end
        item.actualRPM = value
    end

    return {
        baseRPM = baseRPM,
        commands = commands
    }
end

local function mergeData(primary, secondary)
    if type(primary) ~= "table" then
        return secondary
    end
    if type(secondary) ~= "table" then
        return primary
    end

    local result = {}
    for key, value in pairs(primary) do
        result[key] = value
    end
    for key, value in pairs(secondary) do
        if key ~= "order" and key ~= "nodeID" then
            result[key] = value
        end
    end
    return result
end

local function readMeasurements()
    local airspeed, airErr = client.readAirspeed()
    if not airspeed then
        return nil, airErr
    end

    local data = airspeed
    local gnss, gnssErr = client.readGnss()
    if gnss then
        data = mergeData(data, gnss)
    elseif gnssErr then
        data.altitudeErr = gnssErr
    end

    local posSpec = cfg.positionMeasurement
    local speedSpec = cfg.speedMeasurement

    local position = data[posSpec.field]
    if position == nil then
        return nil, data[posSpec.field .. "Err"] or ("Missing field [" .. tostring(posSpec.field) .. "]")
    end

    local speed = data[speedSpec.field]
    if speed == nil then
        return nil, data[speedSpec.field .. "Err"] or ("Missing field [" .. tostring(speedSpec.field) .. "]")
    end

    position = position * (tonumber(posSpec.scale) or 1)
    speed = speed * (tonumber(speedSpec.scale) or 1)

    return {
        raw = data,
        position = position,
        speed = speed
    }
end

print("Altitude experiment")
print("Position target: " .. tostring(positionSetpoint))
print("Outer PID: kp=" .. tostring(outerKp) .. " ki=" .. tostring(outerPidCfg.ki or 0) .. " kd=" .. tostring(outerPidCfg.kd or 0))
print("Inner PID: kp=" .. tostring(innerKp) .. " ki=" .. tostring(innerPidCfg.ki or 0) .. " kd=" .. tostring(innerPidCfg.kd or 0))
print("Position source: " .. tostring(cfg.positionMeasurement.field) .. " scale=" .. tostring(cfg.positionMeasurement.scale or 1))
print("Speed source: " .. tostring(cfg.speedMeasurement.field) .. " scale=" .. tostring(cfg.speedMeasurement.scale or 1))
print("Period: " .. tostring(period))
print("Outputs:")
for _, item in ipairs(outputsCfg) do
    print("  " .. tostring(item.node) .. " / " .. tostring(item.alias) .. "  ratio=" .. tostring(item.ratio))
end
print("Dry run: " .. tostring(dryRun))

while true do
    local measurement, readErr = readMeasurements()

    if not measurement then
        print("ERROR: " .. tostring(readErr))

        if cfg.stopOnSensorError then
            local _, stopErr = setOutputs(0)
            if stopErr then
                print("STOP ERROR: " .. tostring(stopErr))
            end
        end
    else
        local speedTarget, outerInfo = pid.update(outerPid, positionSetpoint, measurement.position, period)
        if speedTarget == nil then
            print("OUTER ERROR: " .. tostring(outerInfo))
        else
            local baseOutput, innerInfo = pid.update(innerPid, speedTarget, measurement.speed, period)
            if baseOutput == nil then
                print("INNER ERROR: " .. tostring(innerInfo))
            else
                local limitedOutput = limitStep(baseOutput)
                local result, outputErr = setOutputs(limitedOutput)

                if result == nil then
                    print("OUTPUT ERROR: " .. tostring(outputErr))
                else
                    print(
                        "pos=" .. tostring(measurement.position) ..
                        " pos_tgt=" .. tostring(positionSetpoint) ..
                        " speed_tgt=" .. tostring(speedTarget) ..
                        " speed=" .. tostring(measurement.speed) ..
                        " base=" .. tostring(result.baseRPM) ..
                        "  " .. describeCommands(result.commands)
                    )
                end
            end
        end
    end

    sleep(period)
end
