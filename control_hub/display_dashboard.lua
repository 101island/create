local args = {...}

local function loadDisplay(name)
    local path = "display/" .. name .. ".lua"
    local fn, err = loadfile(path)
    if not fn then
        error("Could not load display module [" .. name .. "]: " .. tostring(err), 0)
    end
    return fn()
end

local client = dofile("client.lua")
local controlCfg = dofile("control_config.lua")
local pid = dofile("pid.lua")
local core = loadDisplay("core")
local device = loadDisplay("device")
local menu = loadDisplay("menu")
local loop = loadDisplay("loop")
local system = loadDisplay("system")

local function optionalNumber(index, name, default)
    if args[index] == nil then
        return default, true
    end

    local value = tonumber(args[index])
    if value == nil then
        print("ERROR: Invalid " .. name .. ".")
        return nil, false
    end

    return value, true
end

local side = args[1] or "top"
local period, ok = optionalNumber(2, "period", 0.5)
if not ok then return end

local textScale
textScale, ok = optionalNumber(3, "text scale", 0.5)
if not ok then return end

local initialPage = args[4]

if period <= 0 then
    print("ERROR: Invalid period.")
    return
end
if textScale <= 0 then
    print("ERROR: Invalid text scale.")
    return
end

local screen, screenErr = device.wrap(side)
if not screen then
    print("ERROR: " .. tostring(screenErr))
    return
end

core.configure(screen, textScale)

local pages = {
    { label = "INR" },
    { label = "OUT" },
    { label = "IO" }
}
local active = 1
local latestAirspeed = nil
local latestErr = nil
local latestInnerState = nil
local latestOuterState = nil
local latestSystemState = nil

local cfg = client.config()
local targetID = cfg.nodes and cfg.nodes.Airspeed
local gnssID = cfg.nodes and cfg.nodes.GNSS
local status = "TOP  ID " .. tostring(targetID) .. "  " .. tostring(period) .. "s"
local forwardCfg = controlCfg.forwardSpeed or {}
local outerCfg = controlCfg.altitudeExperiment or {}

local function actuatorNodeNames()
    local names = {}
    for nodeName in pairs(cfg.nodes or {}) do
        if nodeName ~= "Airspeed" and nodeName ~= "GNSS" then
            names[#names + 1] = nodeName
        end
    end
    table.sort(names)
    return names
end

local actuatorNodes = actuatorNodeNames()

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

local function buildSystemState(sensorData, actuatorData)
    local sensorItems = {}
    local actuatorItems = {}

    if type(sensorData) == "table" then
        local names = {}
        for key in pairs(sensorData) do
            if key ~= "nodeID" and key ~= "nodeName" and key ~= "order" and key ~= "partial" and key ~= "partialErr" and not key:find("Err$") and not key:find("Method$") then
                names[#names + 1] = key
            end
        end
        table.sort(names)

        for _, name in ipairs(names) do
            sensorItems[#sensorItems + 1] = {
                label = core.label(name),
                value = sensorData[name],
                err = sensorData[name .. "Err"]
            }
        end
    end

    for _, nodeName in ipairs(actuatorNodes) do
        local data = actuatorData[nodeName]
        if type(data) == "table" and type(data.order) == "table" then
            for _, alias in ipairs(data.order) do
                actuatorItems[#actuatorItems + 1] = {
                    label = alias,
                    value = data[alias],
                    err = data[alias .. "Err"]
                }
            end
        else
            actuatorItems[#actuatorItems + 1] = {
                label = nodeName,
                value = nil,
                err = data and data.err or "No data"
            }
        end
    end

    return {
        sensors = sensorItems,
        actuators = actuatorItems
    }
end

local function mergeOrder(primary, secondary)
    local merged = {}
    local seen = {}

    local function addOrder(order)
        if type(order) ~= "table" then
            return
        end
        for _, name in ipairs(order) do
            if not seen[name] then
                seen[name] = true
                merged[#merged + 1] = name
            end
        end
    end

    addOrder(primary and primary.order)
    addOrder(secondary and secondary.order)

    if #merged > 0 then
        table.sort(merged)
    end

    return merged
end

local function newPidState(cfgSection)
    return pid.new({
        kp = cfgSection.kp,
        ki = cfgSection.ki,
        kd = cfgSection.kd,
        bias = cfgSection.bias,
        outputMin = cfgSection.outputMin,
        outputMax = cfgSection.outputMax,
        integralMin = cfgSection.integralMin,
        integralMax = cfgSection.integralMax
    })
end

local innerPidState = newPidState(forwardCfg.pid or {})
local outerPidState = newPidState(outerCfg.outerPid or {})

local lastInnerOutput = nil

local function limitStep(value, maxStep)
    if type(value) ~= "number" then
        return value
    end
    local step = tonumber(maxStep)
    if not step or lastInnerOutput == nil then
        return value
    end

    local delta = value - lastInnerOutput
    if delta > step then
        return lastInnerOutput + step
    end
    if delta < -step then
        return lastInnerOutput - step
    end
    return value
end

local function buildInnerLoopState(data)
    local targetSpeed = forwardCfg.setpoint
    local currentSpeed = data and data.forward or nil
    local speedErr = currentSpeed == nil and (data and data.forwardErr) or nil
    local controlPeriod = tonumber(forwardCfg.period) or period
    local output, info = pid.update(innerPidState, targetSpeed, currentSpeed, controlPeriod)

    if type(output) == "number" then
        output = limitStep(output, forwardCfg.maxStep)
        lastInnerOutput = output
    end

    local errorValue = type(info) == "table" and info.error or nil
    local outputErr = type(info) == "string" and info or speedErr

    return {
        title = "INNER SPD",
        values = {
            { label = "TGT SPD", value = targetSpeed, color = palette and palette.yellow },
            { label = "CUR SPD", value = currentSpeed, err = speedErr, color = palette and palette.lime },
            { label = "ERR", value = errorValue, err = speedErr, color = palette and palette.orange },
            { label = "OUT", value = output, err = outputErr, color = palette and palette.cyan }
        },
        params = {
            { label = "KP", value = (forwardCfg.pid or {}).kp, color = palette and palette.white },
            { label = "KI", value = (forwardCfg.pid or {}).ki, color = palette and palette.white },
            { label = "KD", value = (forwardCfg.pid or {}).kd, color = palette and palette.white }
        }
    }
end

local function buildOuterLoopState(data)
    local targetAltitude = outerCfg.positionSetpoint
    local altitudeField = outerCfg.positionMeasurement and outerCfg.positionMeasurement.field or "altitude"
    local currentAltitude = data and data[altitudeField] or nil
    local altitudeErr = currentAltitude == nil and (data and data[altitudeField .. "Err"]) or nil
    local controlPeriod = tonumber(outerCfg.period) or period
    local targetSpeed, info = pid.update(outerPidState, targetAltitude, currentAltitude, controlPeriod)
    local errorValue = type(info) == "table" and info.error or nil
    local outputErr = type(info) == "string" and info or altitudeErr

    return {
        title = "OUTER ALT",
        values = {
            { label = "TGT ALT", value = targetAltitude, color = palette and palette.yellow },
            { label = "CUR ALT", value = currentAltitude, err = altitudeErr, color = palette and palette.lime },
            { label = "ERR", value = errorValue, err = altitudeErr, color = palette and palette.orange },
            { label = "SPD TGT", value = targetSpeed, err = outputErr, color = palette and palette.cyan }
        },
        params = {
            { label = "KP", value = (outerCfg.outerPid or {}).kp, color = palette and palette.white },
            { label = "KI", value = (outerCfg.outerPid or {}).ki, color = palette and palette.white },
            { label = "KD", value = (outerCfg.outerPid or {}).kd, color = palette and palette.white }
        }
    }
end

local function drawError(message)
    core.clear(screen)
    menu.draw(screen, pages, active, 1)
    core.writeAt(screen, 1, 3, "ERROR", core.palette and core.palette.red)
    core.writeAt(screen, 1, 5, tostring(message), core.palette and core.palette.red)
    core.status(screen, status)
end

local function draw()
    if active == 1 then
        if latestInnerState then
            loop.draw(screen, latestInnerState, status)
            menu.draw(screen, pages, active, 1)
        else
            drawError(latestErr or "No inner loop")
        end
    elseif active == 2 then
        if latestOuterState then
            loop.draw(screen, latestOuterState, status)
            menu.draw(screen, pages, active, 1)
        else
            drawError(latestErr or "No outer loop")
        end
    else
        system.draw(screen, latestSystemState, status)
        menu.draw(screen, pages, active, 1)
    end
end

local function update()
    local actuatorData = {}
    latestAirspeed, latestErr = client.readAirspeed()

    if gnssID then
        local gnssData, gnssErr = client.readGnss()
        if gnssData then
            gnssData.order = mergeOrder(latestAirspeed, gnssData)
            latestAirspeed = mergeData(latestAirspeed or {}, gnssData)
        elseif latestAirspeed then
            latestAirspeed.altitudeErr = gnssErr
        elseif gnssErr then
            latestErr = gnssErr
        end
    end

    for _, nodeName in ipairs(actuatorNodes) do
        local data, err = client.readActuatorNode(nodeName)
        if data then
            actuatorData[nodeName] = data
        else
            actuatorData[nodeName] = {
                err = err
            }
        end
    end

    latestInnerState = latestAirspeed and buildInnerLoopState(latestAirspeed) or nil
    latestOuterState = latestAirspeed and buildOuterLoopState(latestAirspeed) or nil
    latestSystemState = buildSystemState(latestAirspeed, actuatorData)
    draw()
end

if type(initialPage) == "string" then
    for index, page in ipairs(pages) do
        if page.label == initialPage:upper() then
            active = index
            break
        end
    end
end

update()

if type(os.startTimer) ~= "function" or type(os.pullEvent) ~= "function" then
    if type(sleep) ~= "function" then
        print("ERROR: no timer API available.")
        return
    end

    while true do
        sleep(period)
        update()
    end
end

local timer = os.startTimer(period)
while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" and p1 == timer then
        update()
        timer = os.startTimer(period)
    elseif event == "monitor_touch" and p1 == side then
        local selected = menu.hitTest(pages, p2, p3, 1)
        if selected then
            active = selected
            draw()
        end
    elseif event == "key" and keys then
        if p1 == keys.left then
            active = active - 1
            if active < 1 then active = #pages end
            draw()
        elseif p1 == keys.right then
            active = active + 1
            if active > #pages then active = 1 end
            draw()
        end
    end
end
