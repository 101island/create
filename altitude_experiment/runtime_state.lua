local pid = dofile("pid.lua")
local io = dofile("io.lua")
local actuator = dofile("actuator.lua")
local feedforward = dofile("feedforward.lua")

local M = {}

local function nowSeconds()
    if type(os) == "table" and type(os.clock) == "function" then
        return os.clock()
    end
    if type(os) == "table" and type(os.epoch) == "function" then
        return os.epoch("ingame") / 72000
    end
    return nil
end

local function shallowCopy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

local function validMode(mode)
    if mode == "speed" then
        return "speed"
    end
    return "cascade"
end

local function readField(data, spec)
    if type(spec) ~= "table" then
        return nil, "Missing measurement spec"
    end

    local field = spec.field
    if type(field) ~= "string" or field == "" then
        return nil, "Missing measurement field"
    end

    if type(data) ~= "table" then
        return nil, "Missing sensor data"
    end

    local value = data[field]
    if value == nil then
        return nil, data[field .. "Err"] or ("Missing field [" .. tostring(field) .. "]")
    end

    local scale = tonumber(spec.scale) or 1
    return value * scale
end

local pidFields = {
    "kp",
    "ki",
    "kd",
    "bias",
    "outputMin",
    "outputMax",
    "integralMin",
    "integralMax"
}

local function applyPidFields(state, cfg)
    if type(state) ~= "table" or type(cfg) ~= "table" then
        return
    end

    for _, field in ipairs(pidFields) do
        if cfg[field] ~= nil then
            local value = tonumber(cfg[field])
            if value ~= nil then
                state[field] = value
            end
        end
    end

    state.integral = clamp(state.integral or 0, state.integralMin, state.integralMax)
end

local function selectPidSegment(cfg, altitude)
    if type(cfg) ~= "table" or type(cfg.segments) ~= "table" then
        return nil, nil
    end

    local h = tonumber(altitude)
    if h == nil then
        return nil, nil
    end

    for index, segment in ipairs(cfg.segments) do
        local minAltitude = tonumber(segment.altitudeMin)
        local maxAltitude = tonumber(segment.altitudeMax)
        local minOk = minAltitude == nil or h >= minAltitude
        local maxOk = maxAltitude == nil or h < maxAltitude
        if minOk and maxOk then
            return segment, segment.name or tostring(index)
        end
    end

    return nil, nil
end

local function applyPidSchedule(state, cfg, altitude)
    applyPidFields(state, cfg)

    local segment, segmentName = selectPidSegment(cfg, altitude)
    if segment then
        applyPidFields(state, segment)
    end

    return segmentName or "base"
end

function M.new(options)
    options = options or {}

    local hardwareCfg = dofile("config.lua")
    local controlRoot = dofile("control_config.lua")
    local controlCfg = controlRoot.altitudeExperiment or {}

    local runtime = {
        hardware = hardwareCfg,
        config = controlCfg,
        enabled = options.enabled,
        mode = validMode(options.mode or controlCfg.mode),
        period = tonumber(options.period) or tonumber(controlCfg.period) or 0.2,
        displayPeriod = tonumber(options.displayPeriod) or tonumber(controlCfg.displayPeriod) or 0.5,
        dryRun = options.dryRun == true,
        setpoints = {
            altitude = tonumber(options.positionSetpoint) or tonumber(controlCfg.positionSetpoint) or 0,
            speed = tonumber(options.speedSetpoint) or tonumber(controlCfg.speedSetpoint) or 0
        },
        outputCfg = controlCfg.outputs or {},
        positionSpec = controlCfg.positionMeasurement or {},
        speedSpec = controlCfg.speedMeasurement or {},
        outerPid = pid.new(controlCfg.outerPid or {}),
        innerPid = pid.new(controlCfg.innerPid or {}),
        feedforward = feedforward.new(controlCfg.feedforward or {}),
        maxStep = tonumber(controlCfg.maxStep),
        stopOnSensorError = controlCfg.stopOnSensorError ~= false,
        lastBaseOutput = nil,
        lastStepTime = nil,
        io = {
            sensors = nil,
            actuators = nil
        },
        position = {},
        speed = {},
        output = {},
        feedforwardState = {},
        history = {
            max = tonumber(controlCfg.plotHistory) or 120,
            samples = {}
        },
        status = "init"
    }

    if runtime.enabled == nil then
        runtime.enabled = controlCfg.enabled ~= false
    end

    if options.outerKp ~= nil then
        runtime.outerPid.kp = tonumber(options.outerKp) or runtime.outerPid.kp
        if type(runtime.config.outerPid) == "table" then
            runtime.config.outerPid.kp = runtime.outerPid.kp
        end
    end
    if options.innerKp ~= nil then
        runtime.innerPid.kp = tonumber(options.innerKp) or runtime.innerPid.kp
        if type(runtime.config.innerPid) == "table" then
            runtime.config.innerPid.kp = runtime.innerPid.kp
        end
    end

    return runtime
end

function M.reset(runtime)
    pid.reset(runtime.outerPid)
    pid.reset(runtime.innerPid)
    runtime.lastBaseOutput = nil
end

function M.setEnabled(runtime, enabled)
    runtime.enabled = enabled == true
    if not runtime.enabled then
        M.reset(runtime)
    end
end

function M.toggleEnabled(runtime)
    M.setEnabled(runtime, not runtime.enabled)
end

function M.toggleMode(runtime)
    if runtime.mode == "cascade" then
        runtime.mode = "speed"
    else
        runtime.mode = "cascade"
    end
    M.reset(runtime)
end

function M.adjustSetpoint(runtime, name, delta)
    local current = tonumber(runtime.setpoints[name]) or 0
    runtime.setpoints[name] = current + delta
end

function M.adjustPid(runtime, loopName, field, delta)
    local target
    local cfg
    if loopName == "outer" then
        target = runtime.outerPid
        cfg = runtime.config and runtime.config.outerPid
    elseif loopName == "inner" then
        target = runtime.innerPid
        cfg = runtime.config and runtime.config.innerPid
    end
    if not target then
        return nil, "Unknown PID loop [" .. tostring(loopName) .. "]"
    end

    local current = tonumber(target[field]) or 0
    target[field] = current + delta
    if type(cfg) == "table" then
        cfg[field] = target[field]
    end
    return target[field]
end

local function limitStep(runtime, value)
    local maxStep = tonumber(runtime.maxStep)
    if not maxStep or runtime.lastBaseOutput == nil then
        return value
    end

    local delta = value - runtime.lastBaseOutput
    if delta > maxStep then
        return runtime.lastBaseOutput + maxStep
    end
    if delta < -maxStep then
        return runtime.lastBaseOutput - maxStep
    end
    return value
end

local function buildCommands(runtime, baseOutput)
    local commands = {}

    for _, item in ipairs(runtime.outputCfg or {}) do
        local ratio = tonumber(item.ratio) or 0
        commands[#commands + 1] = {
            alias = item.alias,
            ratio = ratio,
            command = baseOutput * ratio
        }
    end

    return commands
end

local function clampActuatorCommand(runtime, value)
    local model = runtime.feedforward or {}
    return clamp(value, model.outputMin or 0, model.outputMax or 15)
end

local function applyCommands(runtime, baseOutput)
    local commands = buildCommands(runtime, baseOutput)

    if runtime.dryRun then
        return {
            base = baseOutput,
            commands = commands,
            dryRun = true
        }
    end

    for _, item in ipairs(commands) do
        local result, err = actuator.setOutput(runtime.hardware, item.alias, item.command)
        if not result then
            item.err = err
            return nil, item.alias .. ": " .. tostring(err), commands
        end
        item.output = result.output
        item.exactOutput = result.exactOutput
        item.method = result.method
    end

    return {
        base = baseOutput,
        commands = commands,
        dryRun = false
    }
end

local function stopOutputs(runtime)
    runtime.lastBaseOutput = 0
    local result, err, commands = applyCommands(runtime, 0)
    runtime.output = result or {
        base = 0,
        commands = commands or {},
        err = err
    }
    return result, err
end

local function feedforwardAltitude(runtime, position)
    local model = runtime.feedforward or {}
    if model.source == "current" then
        return position
    end
    if model.source == "speedTarget" then
        return runtime.position and runtime.position.output or position
    end
    return runtime.setpoints.altitude or position
end

local function updateActuatorSnapshot(runtime)
    runtime.io.actuators = actuator.readAll(runtime.hardware)
end

local function pushHistory(runtime, timestamp)
    local history = runtime.history
    if type(history) ~= "table" then
        return
    end

    local samples = history.samples
    if type(samples) ~= "table" then
        samples = {}
        history.samples = samples
    end

    samples[#samples + 1] = {
        t = timestamp or nowSeconds(),
        altitude = runtime.position.current,
        altitudeTarget = runtime.position.target,
        speed = runtime.speed.current,
        speedTarget = runtime.speed.target,
        output = runtime.output and runtime.output.base,
        feedforward = runtime.output and runtime.output.feedforward,
        correction = runtime.output and runtime.output.correction,
        status = runtime.status
    }

    local maxSamples = tonumber(history.max) or 120
    while #samples > maxSamples do
        table.remove(samples, 1)
    end
end

function M.step(runtime, options)
    options = options or {}
    local applyOutput = options.applyOutput ~= false
    local configuredDt = tonumber(options.dt)
    local now = nowSeconds()
    local dt = configuredDt

    if not dt then
        if now and runtime.lastStepTime then
            dt = now - runtime.lastStepTime
        else
            dt = runtime.period
        end
    end
    if now then
        runtime.lastStepTime = now
    end
    if not dt or dt <= 0 then
        dt = runtime.period
    end

    runtime.io.sensors = io.readSensors(runtime.hardware)
    local sensors = runtime.io.sensors

    local position, positionErr = readField(sensors, runtime.positionSpec)
    local speed, speedErr = readField(sensors, runtime.speedSpec)
    local outerSegment = applyPidSchedule(runtime.outerPid, runtime.config.outerPid, position)
    local innerSegment = applyPidSchedule(runtime.innerPid, runtime.config.innerPid, position)

    runtime.position = {
        target = runtime.setpoints.altitude,
        current = position,
        err = positionErr,
        error = position and (runtime.setpoints.altitude - position) or nil,
        pidSegment = outerSegment
    }
    runtime.speed = {
        target = runtime.setpoints.speed,
        current = speed,
        err = speedErr,
        error = speed and (runtime.setpoints.speed - speed) or nil,
        pidSegment = innerSegment
    }

    if positionErr or speedErr then
        runtime.status = positionErr or speedErr
        if runtime.enabled and runtime.stopOnSensorError and applyOutput then
            stopOutputs(runtime)
        else
            runtime.output = {
                base = nil,
                commands = {},
                err = runtime.status
            }
        end
        updateActuatorSnapshot(runtime)
        pushHistory(runtime, now)
        return nil, runtime.status
    end

    local speedTarget = runtime.setpoints.speed
    local outerInfo = nil
    local outerErr = nil

    if runtime.mode == "cascade" then
        if runtime.enabled then
            speedTarget, outerInfo = pid.update(runtime.outerPid, runtime.setpoints.altitude, position, dt, type(speed) == "number" and -speed or nil)
            outerErr = type(outerInfo) == "string" and outerInfo or nil
        else
            outerInfo = {
                error = runtime.setpoints.altitude - position,
                integral = runtime.outerPid.integral,
                derivative = 0
            }
        end
    end

    runtime.position.output = speedTarget
    runtime.position.pid = outerInfo
    runtime.position.err = runtime.position.err or outerErr

    if type(speedTarget) ~= "number" then
        runtime.status = tostring(outerErr or "Invalid speed target")
        if runtime.enabled and runtime.stopOnSensorError and applyOutput then
            stopOutputs(runtime)
        end
        updateActuatorSnapshot(runtime)
        pushHistory(runtime, now)
        return nil, runtime.status
    end

    runtime.speed.target = speedTarget
    runtime.speed.error = speedTarget - speed

    if not runtime.enabled then
        runtime.status = "disabled"
        if applyOutput then
            stopOutputs(runtime)
        else
            runtime.output = {
                base = 0,
                commands = buildCommands(runtime, 0),
                disabled = true
            }
        end
        updateActuatorSnapshot(runtime)
        pushHistory(runtime, now)
        return runtime
    end

    local ffAltitude = feedforwardAltitude(runtime, position)
    local ff, ffErr = feedforward.evaluate(runtime.feedforward, ffAltitude)
    if not ff then
        ff = {
            level = 0,
            fill = 0,
            density = nil
        }
    end
    runtime.feedforwardState = {
        altitude = ffAltitude,
        level = ff.level,
        fill = ff.fill,
        density = ff.density,
        err = ffErr
    }

    local correction, innerInfo = pid.update(runtime.innerPid, speedTarget, speed, dt)
    local innerErr = type(innerInfo) == "string" and innerInfo or nil

    runtime.speed.pid = innerInfo
    runtime.speed.err = runtime.speed.err or innerErr

    if type(correction) ~= "number" then
        runtime.status = tostring(innerErr or "Invalid output")
        if runtime.stopOnSensorError and applyOutput then
            stopOutputs(runtime)
        end
        updateActuatorSnapshot(runtime)
        pushHistory(runtime, now)
        return nil, runtime.status
    end

    local requestedOutput = (tonumber(ff.level) or 0) + correction
    local baseOutput = clampActuatorCommand(runtime, requestedOutput)
    baseOutput = limitStep(runtime, baseOutput)
    runtime.lastBaseOutput = baseOutput

    local result, outputErr, commands
    if applyOutput then
        result, outputErr, commands = applyCommands(runtime, baseOutput)
    else
        commands = buildCommands(runtime, baseOutput)
        result = {
            base = baseOutput,
            commands = commands,
            preview = true
        }
    end

    runtime.output = result or {
        base = baseOutput,
        commands = commands or {},
        err = outputErr
    }
    runtime.output.requested = requestedOutput
    runtime.output.feedforward = ff.level
    runtime.output.feedforwardFill = ff.fill
    runtime.output.pressure = ff.density
    runtime.output.correction = correction
    runtime.output.innerSegment = innerSegment
    runtime.output.outerSegment = outerSegment
    runtime.output.feedforwardErr = ffErr

    runtime.status = outputErr or ffErr or "ok"
    updateActuatorSnapshot(runtime)
    pushHistory(runtime, now)

    return outputErr and nil or runtime, outputErr
end

local function formatNumber(value)
    if type(value) == "number" then
        return string.format("%.2f", value)
    end
    return tostring(value)
end

function M.summary(runtime)
    local parts = {
        "mode=" .. tostring(runtime.mode),
        "en=" .. tostring(runtime.enabled),
        "alt=" .. formatNumber(runtime.position.current),
        "alt_tgt=" .. formatNumber(runtime.position.target),
        "spd=" .. formatNumber(runtime.speed.current),
        "spd_tgt=" .. formatNumber(runtime.speed.target),
        "ff=" .. formatNumber(runtime.output and runtime.output.feedforward),
        "cor=" .. formatNumber(runtime.output and runtime.output.correction),
        "out=" .. formatNumber(runtime.output and runtime.output.base),
        "seg=" .. tostring(runtime.output and runtime.output.innerSegment),
        "status=" .. tostring(runtime.status)
    }

    local commands = runtime.output and runtime.output.commands or {}
    for _, item in ipairs(commands) do
        parts[#parts + 1] = tostring(item.alias) .. "=" .. formatNumber(item.output or item.command)
    end

    return table.concat(parts, "  ")
end

function M.snapshot(runtime)
    return {
        enabled = runtime.enabled,
        mode = runtime.mode,
        setpoints = shallowCopy(runtime.setpoints),
        position = shallowCopy(runtime.position),
        speed = shallowCopy(runtime.speed),
        output = runtime.output,
        feedforward = runtime.feedforwardState,
        history = runtime.history,
        io = runtime.io,
        status = runtime.status,
        innerPid = runtime.innerPid,
        outerPid = runtime.outerPid
    }
end

return M
