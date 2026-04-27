local function loadDisplay(name)
    local paths = {
        "display/" .. name .. ".lua",
        name .. ".lua"
    }

    local lastErr
    for _, path in ipairs(paths) do
        local fn, err = loadfile(path)
        if fn then
            return fn()
        end
        lastErr = err
    end

    error("Could not load display module [" .. name .. "]: " .. tostring(lastErr), 0)
end

local core = loadDisplay("core")
local M = {}

local palette = core.palette

local marks = { "#", "*", "+", "o" }

local function valueRange(series)
    local minValue
    local maxValue

    for _, item in ipairs(series or {}) do
        for _, value in ipairs(item.values or {}) do
            if type(value) == "number" then
                minValue = minValue and math.min(minValue, value) or value
                maxValue = maxValue and math.max(maxValue, value) or value
            end
        end
    end

    if minValue == nil or maxValue == nil then
        return -1, 1
    end
    if minValue == maxValue then
        return minValue - 1, maxValue + 1
    end

    return minValue, maxValue
end

local function hasSamples(series)
    for _, item in ipairs(series or {}) do
        for _, value in ipairs(item.values or {}) do
            if type(value) == "number" then
                return true
            end
        end
    end

    return false
end

local function mapY(value, minValue, maxValue, top, height)
    local ratio = (value - minValue) / (maxValue - minValue)
    ratio = math.max(0, math.min(1, ratio))
    return top + height - 1 - math.floor(ratio * (height - 1) + 0.5)
end

function M.push(history, name, value, limit)
    history[name] = history[name] or {}

    local values = history[name]
    values[#values + 1] = value

    while #values > limit do
        table.remove(values, 1)
    end
end

function M.draw(display, opts)
    opts = opts or {}
    core.clear(display)

    local width, height = display.getSize()
    local title = opts.title or "PLOT"
    local top = opts.top or 3
    local bottom = opts.bottom or (height - 2)
    local left = opts.left or 1
    local right = opts.right or width
    local plotHeight = bottom - top + 1
    local plotWidth = right - left + 1

    core.writeAt(display, 1, 1, title:sub(1, width), palette and palette.cyan)

    if plotHeight < 2 or plotWidth < 4 then
        core.writeAt(display, 1, 3, "Display too small", palette and palette.red)
        core.status(display, opts.status)
        return
    end

    if not hasSamples(opts.series) then
        core.writeAt(display, 1, 2, "NO SAMPLES", palette and palette.red)
        core.writeAt(display, 1, 4, "Wait for airspeed data", palette and palette.white)
        core.status(display, opts.status)
        return
    end

    local minValue, maxValue = valueRange(opts.series)
    core.writeAt(display, 1, 2, string.format("%.2f..%.2f", minValue, maxValue):sub(1, width), palette and palette.gray)

    for y = top, bottom do
        core.writeAt(display, left, y, string.rep(".", plotWidth), palette and palette.gray)
    end

    for seriesIndex, item in ipairs(opts.series or {}) do
        local values = item.values or {}
        local mark = item.mark or marks[((seriesIndex - 1) % #marks) + 1]
        local color = item.color or palette and palette.lime
        local first = math.max(1, #values - plotWidth + 1)

        for i = first, #values do
            local value = values[i]
            if type(value) == "number" then
                local x = left + (i - first)
                local y = mapY(value, minValue, maxValue, top, plotHeight)
                core.writeAt(display, x, y, mark, color)
            end
        end
    end

    local legend = {}
    for index, item in ipairs(opts.series or {}) do
        legend[#legend + 1] = (item.mark or marks[((index - 1) % #marks) + 1]) .. "=" .. tostring(item.name)
    end
    if #legend > 0 and height >= 2 then
        core.writeAt(display, 1, height - 1, table.concat(legend, " "):sub(1, width), palette and palette.white)
    end

    core.status(display, opts.status)
end

return M
