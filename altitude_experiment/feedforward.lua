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

local function addPoint(points, altitude, value, slope)
    points[#points + 1] = {
        altitude = altitude,
        value = value,
        slope = slope
    }
end

local function copyLevelPoints(source)
    if type(source) ~= "table" then
        return nil
    end

    local points = {}
    for _, item in ipairs(source) do
        local altitude
        local level
        if type(item) == "table" then
            altitude = tonumber(item.altitude or item[1])
            level = tonumber(item.level or item.value or item[2])
        end
        if altitude ~= nil and level ~= nil then
            points[#points + 1] = {
                altitude = altitude,
                level = level
            }
        end
    end

    table.sort(points, function(left, right)
        return left.altitude < right.altitude
    end)

    if #points == 0 then
        return nil
    end
    return points
end

local function interpolateLevel(points, altitude)
    local h = tonumber(altitude)
    if h == nil then
        return nil, "Invalid altitude"
    end

    local count = #points
    if count == 1 then
        return points[1].level
    end

    local left = points[1]
    local right = points[2]
    if h >= points[count].altitude then
        left = points[count - 1]
        right = points[count]
    else
        for index = 2, count do
            if h <= points[index].altitude then
                left = points[index - 1]
                right = points[index]
                break
            end
        end
    end

    local span = right.altitude - left.altitude
    if span == 0 then
        return left.level
    end

    local ratio = (h - left.altitude) / span
    return left.level + (right.level - left.level) * ratio
end

local function evaluatePressure(points, altitude)
    local h = tonumber(altitude)
    if h == nil then
        return nil, "Invalid altitude"
    end

    local count = #points
    if count == 0 then
        return 1
    end
    if count == 1 then
        return points[1].value
    end

    local index = -1
    for i = 1, count do
        if h < points[i].altitude then
            break
        end
        index = i
    end

    if index == -1 then
        return points[1].value
    end
    if index >= count then
        return points[count].value
    end

    local p1 = points[index]
    local p2 = points[index + 1]
    local dx = p2.altitude - p1.altitude
    if dx == 0 then
        return p1.value
    end

    local dy = p2.value - p1.value
    local t = (h - p1.altitude) / dx
    local s1 = p1.slope
    local s2 = p2.slope

    local cubic = (s1 + s2) * dx - 2 * dy
    local quadratic = 3 * dy - (2 * s1 + s2) * dx
    local linear = dx * s1

    local result = ((cubic * t + quadratic) * t + linear) * t + p1.value
    return math.max(result, 0)
end

local function createDefaultPressureCurve(cfg)
    cfg = cfg or {}

    local seaLevel = tonumber(cfg.seaLevel) or 63
    local minY = tonumber(cfg.minY) or -64
    local logicalHeight = tonumber(cfg.logicalHeight) or 704
    local baseSlope = tonumber(cfg.baseSlope) or -0.004
    local maxPressure = tonumber(cfg.maxPressure) or 1.5
    local maxStep = tonumber(cfg.maxStep) or 200
    local smoothingMargin = tonumber(cfg.smoothingMargin) or 40

    local currentAltitude = minY
    local maxAltitude = currentAltitude + logicalHeight
    local smoothingAltitude = maxAltitude - smoothingMargin
    local points = {}

    currentAltitude = math.max(currentAltitude, math.log(maxPressure) / baseSlope + seaLevel)

    while true do
        local pressure = math.exp(baseSlope * (currentAltitude - seaLevel))
        local slope = pressure * baseSlope
        addPoint(points, currentAltitude, pressure, slope)

        if currentAltitude < seaLevel and currentAltitude + maxStep >= seaLevel then
            currentAltitude = seaLevel
        elseif currentAltitude < smoothingAltitude and currentAltitude + maxStep >= smoothingAltitude then
            currentAltitude = smoothingAltitude
        elseif currentAltitude >= smoothingAltitude then
            break
        else
            currentAltitude = currentAltitude + maxStep
        end
    end

    local smoothingPressure = points[#points].value
    local finalSlope = -2 * smoothingPressure / (maxAltitude - smoothingAltitude)
    addPoint(points, maxAltitude, 0, finalSlope)

    return points
end

function M.new(cfg)
    cfg = cfg or {}

    local pressureCfg = cfg.pressure or {}
    local points = pressureCfg.points
    if type(points) ~= "table" then
        points = createDefaultPressureCurve(pressureCfg)
    end

    local referenceAltitude = tonumber(cfg.referenceAltitude) or 205
    local referenceLevel = tonumber(cfg.referenceLevel) or 7
    local maxSteamOutput = tonumber(cfg.maxSteamOutput) or 200
    local capacity = tonumber(cfg.capacity) or 122
    local outputMin = tonumber(cfg.outputMin) or 0
    local outputMax = tonumber(cfg.outputMax) or 15
    local referenceFill = maxSteamOutput * referenceLevel / 15
    local levelPoints = copyLevelPoints(cfg.levels or cfg.levelPoints)

    return {
        enabled = cfg.enabled ~= false,
        source = cfg.source or "target",
        levelPoints = levelPoints,
        points = points,
        referenceAltitude = referenceAltitude,
        referenceLevel = referenceLevel,
        referenceFill = referenceFill,
        maxSteamOutput = maxSteamOutput,
        capacity = capacity,
        outputMin = outputMin,
        outputMax = outputMax
    }
end

function M.evaluate(model, altitude)
    if type(model) ~= "table" or model.enabled == false then
        return {
            level = 0,
            fill = 0,
            density = nil
        }
    end

    local h = tonumber(altitude)
    if h == nil then
        return nil, "Invalid feedforward altitude"
    end

    if type(model.levelPoints) == "table" then
        local level, levelErr = interpolateLevel(model.levelPoints, h)
        if level == nil then
            return nil, levelErr
        end
        level = clamp(level, model.outputMin, model.outputMax)
        return {
            level = level,
            fill = nil,
            density = nil,
            source = "levelPoints"
        }
    end

    local density, densityErr = evaluatePressure(model.points, h)
    if density == nil then
        return nil, densityErr
    end
    if density <= 0 then
        density = 0.000001
    end

    local referenceDensity = evaluatePressure(model.points, model.referenceAltitude) or 1
    local fill = model.referenceFill * (referenceDensity / density)
    fill = clamp(fill, 0, model.capacity)

    local level = fill / model.maxSteamOutput * 15
    level = clamp(level, model.outputMin, model.outputMax)

    return {
        level = level,
        fill = fill,
        density = density,
        referenceDensity = referenceDensity
    }
end

return M
