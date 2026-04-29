local args = {...}

local actuator = dofile("actuator.lua")
local cfg = dofile("config.lua")
local controlRoot = dofile("control_config.lua")
local dataLogger = dofile("data_logger.lua")
local feedforward = dofile("feedforward.lua")
local io = dofile("io.lua")

local controlCfg = controlRoot.altitudeExperiment or {}
local ffModel = feedforward.new(controlCfg.feedforward or {})

local alias = "TopThruster"
local baseArg = args[1]
local amplitude = tonumber(args[2]) or 1
local holdSeconds = tonumber(args[3]) or 5
local cycles = tonumber(args[4]) or 6
local period = tonumber(args[5]) or tonumber(controlCfg.period) or 0.2
local logPath = args[6] or "altitude_id.csv"

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

local function readAltitude()
    local sensors = io.readSensors(cfg)
    return sensors and sensors.altitude, sensors
end

local function estimateBase()
    local altitude = readAltitude()
    if altitude == nil then
        return 7
    end

    local ff = feedforward.evaluate(ffModel, altitude)
    if type(ff) == "table" and type(ff.level) == "number" then
        return ff.level
    end
    return 7
end

local baseLevel
if baseArg == nil or baseArg == "auto" then
    baseLevel = estimateBase()
else
    baseLevel = tonumber(baseArg)
end

if baseLevel == nil or period <= 0 or holdSeconds <= 0 or cycles <= 0 then
    print("Usage: collect_identification.lua [base|auto] [amplitude] [holdSeconds] [cycles] [period] [logPath]")
    print("Example: collect_identification.lua auto 1 5 6 0.2 altitude_id.csv")
    return
end

local logger = dataLogger.new({
    enabled = true,
    path = logPath,
    decimation = 1
})

if not logger.enabled then
    print("ERROR: logger disabled: " .. tostring(logger.err))
    return
end

local outputMin = ffModel.outputMin or 0
local outputMax = ffModel.outputMax or 15
local lowLevel = clamp(baseLevel - amplitude, outputMin, outputMax)
local highLevel = clamp(baseLevel + amplitude, outputMin, outputMax)
local stepsPerHold = math.max(1, math.floor(holdSeconds / period + 0.5))

local function buildRuntime(commandLevel, actualOutput, sensors, status)
    sensors = sensors or {}

    return {
        mode = "ident",
        enabled = true,
        position = {
            target = baseLevel,
            current = sensors.altitude,
            error = nil
        },
        speed = {
            target = 0,
            current = sensors.down,
            error = nil
        },
        output = {
            base = commandLevel,
            commands = {
                {
                    alias = alias,
                    command = commandLevel,
                    output = actualOutput
                }
            },
            feedforward = baseLevel,
            correction = commandLevel - baseLevel,
            pressure = nil,
            innerSegment = "ident",
            outerSegment = "ident"
        },
        status = status or "ok"
    }
end

local function sample(commandLevel)
    local result, err = actuator.setOutput(cfg, alias, commandLevel)
    local _, sensors = readAltitude()
    local actualOutput = result and result.output or nil
    local status = err or "ok"

    dataLogger.write(logger, buildRuntime(commandLevel, actualOutput, sensors, status))

    print(
        "cmd=" .. tostring(commandLevel) ..
        " out=" .. tostring(actualOutput) ..
        " alt=" .. tostring(sensors and sensors.altitude) ..
        " down=" .. tostring(sensors and sensors.down) ..
        " status=" .. tostring(status)
    )
end

print("Identification collection")
print("base=" .. tostring(baseLevel) .. " low=" .. tostring(lowLevel) .. " high=" .. tostring(highLevel))
print("hold=" .. tostring(holdSeconds) .. "s cycles=" .. tostring(cycles) .. " period=" .. tostring(period))
print("log=" .. tostring(logPath))

for cycle = 1, cycles do
    local commandLevel = cycle % 2 == 1 and highLevel or lowLevel
    for _ = 1, stepsPerHold do
        sample(commandLevel)
        sleep(period)
    end
end

actuator.setOutput(cfg, alias, baseLevel)
print("Done. Output returned to base=" .. tostring(baseLevel))
