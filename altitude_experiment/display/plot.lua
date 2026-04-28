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

local function valueAt(sample, key)
    if type(sample) ~= "table" then
        return nil
    end
    return sample[key]
end

local function bounds(samples, series)
    local minValue = nil
    local maxValue = nil

    for _, sample in ipairs(samples or {}) do
        for _, item in ipairs(series or {}) do
            local value = valueAt(sample, item.key)
            if type(value) == "number" then
                if minValue == nil or value < minValue then
                    minValue = value
                end
                if maxValue == nil or value > maxValue then
                    maxValue = value
                end
            end
        end
    end

    if minValue == nil or maxValue == nil then
        return 0, 1
    end
    if minValue == maxValue then
        return minValue - 1, maxValue + 1
    end
    return minValue, maxValue
end

local function plotY(value, minValue, maxValue, top, height)
    if type(value) ~= "number" then
        return nil
    end
    local ratio = (value - minValue) / (maxValue - minValue)
    if ratio < 0 then ratio = 0 end
    if ratio > 1 then ratio = 1 end
    return top + height - 1 - math.floor(ratio * (height - 1) + 0.5)
end

local function drawFrame(display, x, y, width, height)
    if width < 3 or height < 3 then
        return
    end

    local horizontal = string.rep("-", width - 2)
    core.writeAt(display, x, y, "+" .. horizontal .. "+", palette and palette.gray)
    for row = y + 1, y + height - 2 do
        core.writeAt(display, x, row, "|", palette and palette.gray)
        core.writeAt(display, x + width - 1, row, "|", palette and palette.gray)
    end
    core.writeAt(display, x, y + height - 1, "+" .. horizontal .. "+", palette and palette.gray)
end

local function sampleForColumn(samples, col, width)
    local count = #samples
    if count == 0 then
        return nil
    end
    if width <= 1 then
        return samples[count]
    end

    local index = count - width + col
    if index < 1 then
        return nil
    end
    return samples[index]
end

local function drawChart(display, x, y, width, height, title, samples, series)
    if width < 12 or height < 5 then
        return
    end

    local plotX = x + 1
    local plotYTop = y + 2
    local plotWidth = width - 2
    local plotHeight = height - 3
    local minValue, maxValue = bounds(samples, series)

    core.writeAt(display, x, y, tostring(title), palette and palette.cyan)
    core.writeAt(display, x + 10, y, string.format("%.1f..%.1f", minValue, maxValue), palette and palette.gray)
    drawFrame(display, x, y + 1, width, height - 1)

    for col = 1, plotWidth do
        local sample = sampleForColumn(samples, col, plotWidth)
        if sample then
            for _, item in ipairs(series or {}) do
                local value = valueAt(sample, item.key)
                local row = plotY(value, minValue, maxValue, plotYTop, plotHeight)
                if row then
                    core.writeAt(display, plotX + col - 1, row, item.char or "*", item.color)
                end
            end
        end
    end
end

function M.draw(display, runtime, status)
    core.clear(display)

    local width, height = display.getSize()
    local title = "PLOT"
    core.writeAt(display, math.max(1, math.floor((width - #title) / 2) + 1), 1, title, palette and palette.cyan)

    local samples = runtime.history and runtime.history.samples or {}
    local available = math.max(0, height - 4)
    local chartHeight = math.floor(available / 2)

    if chartHeight < 5 then
        core.writeAt(display, 1, 3, "screen too small", palette and palette.red)
        core.status(display, status)
        return
    end

    drawChart(display, 1, 3, width, chartHeight, "SPD .cur -tgt", samples, {
        { key = "speed", char = "*", color = palette and palette.lime },
        { key = "speedTarget", char = "-", color = palette and palette.yellow }
    })

    drawChart(display, 1, 3 + chartHeight, width, chartHeight, "ALT .cur -tgt", samples, {
        { key = "altitude", char = "*", color = palette and palette.lime },
        { key = "altitudeTarget", char = "-", color = palette and palette.yellow }
    })

    core.status(display, status)
end

return M
