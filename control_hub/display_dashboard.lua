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
local core = loadDisplay("core")
local device = loadDisplay("device")
local menu = loadDisplay("menu")
local airspeed = loadDisplay("airspeed")
local flight = loadDisplay("flight")
local plot = loadDisplay("plot")

local plotMarks = { "*", "-", "+", "#", "o", "x" }
local plotColors = {
    function() return core.palette and core.palette.lime end,
    function() return core.palette and core.palette.yellow end,
    function() return core.palette and core.palette.cyan end,
    function() return core.palette and core.palette.orange end,
    function() return core.palette and core.palette.pink end,
    function() return core.palette and core.palette.white end
}

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

local function readTargetConfig()
    local displayCfg = controlCfg.display and controlCfg.display.dashboard or {}
    local targets = displayCfg.targets or {}
    local sources = displayCfg.sources or {}
    local forwardCfg = controlCfg.forwardSpeed or {}
    local metrics = {}

    if type(displayCfg.metrics) == "table" and #displayCfg.metrics > 0 then
        for _, item in ipairs(displayCfg.metrics) do
            if type(item) == "table" and type(item.key) == "string" then
                local target = item.target
                if target == nil and item.key == "speed" then
                    target = forwardCfg.setpoint
                end

                metrics[#metrics + 1] = {
                    key = item.key,
                    label = item.label or core.label(item.key),
                    source = item.source or sources[item.key] or item.key,
                    target = target ~= nil and target or targets[item.key]
                }
            end
        end
    end

    if #metrics == 0 then
        local speedTarget = targets.speed
        if speedTarget == nil then
            speedTarget = forwardCfg.setpoint
        end

        metrics = {
            {
                key = "speed",
                label = "Speed",
                source = sources.speed or "forward",
                target = speedTarget
            },
            {
                key = "height",
                label = "Height",
                source = sources.height or "altitude",
                target = targets.height
            }
        }
    end

    return {
        metrics = metrics
    }
end

local side = args[1] or "top"
local period, ok = optionalNumber(2, "period", 0.5)
if not ok then return end

local textScale
textScale, ok = optionalNumber(3, "text scale", 0.5)
if not ok then return end

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
    { label = "AIR" },
    { label = "PLOT" },
    { label = "FC" }
}
local active = 1
local latestAirspeed = nil
local latestErr = nil
local latestState = nil
local history = {}
local viewCfg = readTargetConfig()

local cfg = client.config()
local targetID = cfg.nodes and cfg.nodes.Airspeed
local gnssID = cfg.nodes and cfg.nodes.GNSS
local status = "TOP  ID " .. tostring(targetID) .. "  " .. tostring(period) .. "s"

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

local function buildState(data)
    local metrics = {}

    for _, spec in ipairs(viewCfg.metrics) do
        local source = spec.source
        metrics[#metrics + 1] = {
            key = spec.key,
            label = spec.label,
            source = source,
            current = data and data[source] or nil,
            currentErr = data and data[source .. "Err"] or nil,
            target = spec.target
        }
    end

    return {
        metrics = metrics
    }
end

local function sourceNameSet()
    local names = {}
    for _, spec in ipairs(viewCfg.metrics) do
        if type(spec.source) == "string" and spec.source ~= "" then
            names[spec.source] = true
        end
    end
    return names
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

    for name in pairs(sourceNameSet()) do
        if not seen[name] then
            merged[#merged + 1] = name
        end
    end

    if #merged > 0 then
        table.sort(merged)
    end

    return merged
end

local function addSamples(state)
    if not state or type(state.metrics) ~= "table" then
        return
    end

    local width = screen.getSize()
    local limit = math.max(8, width - 2)
    for _, item in ipairs(state.metrics) do
        if type(item.current) == "number" then
            plot.push(history, item.key .. "_current", item.current, limit)
        end
        if type(item.target) == "number" then
            plot.push(history, item.key .. "_target", item.target, limit)
        end
    end
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
        if latestState then
            airspeed.draw(screen, latestState, status)
            menu.draw(screen, pages, active, 1)
        else
            drawError(latestErr or "No airspeed")
        end
    elseif active == 2 then
        local series = {}
        for index, spec in ipairs(viewCfg.metrics) do
            local baseColor = plotColors[((index - 1) % #plotColors) + 1]()
            local targetColor = plotColors[(index % #plotColors) + 1]()
            local shortLabel = (spec.label or spec.key):upper():sub(1, 3)

            series[#series + 1] = {
                name = shortLabel .. " CUR",
                values = history[spec.key .. "_current"] or {},
                color = baseColor,
                mark = plotMarks[((index - 1) % #plotMarks) + 1]
            }
            series[#series + 1] = {
                name = shortLabel .. " TGT",
                values = history[spec.key .. "_target"] or {},
                color = targetColor,
                mark = plotMarks[(index % #plotMarks) + 1]
            }
        end

        plot.draw(screen, {
            title = "X-T",
            top = 4,
            series = series,
            status = status
        })
        menu.draw(screen, pages, active, 1)
    else
        flight.draw(screen, {}, status)
        menu.draw(screen, pages, active, 1)
    end
end

local function update()
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

    latestState = latestAirspeed and buildState(latestAirspeed) or nil
    addSamples(latestState)
    draw()
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
