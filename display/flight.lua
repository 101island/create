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

local attitudeRows = {
    { key = "roll", label = "Roll" },
    { key = "pitch", label = "Pitch" },
    { key = "yaw", label = "Yaw" }
}

local rateRows = {
    { key = "p", label = "P Roll" },
    { key = "q", label = "Q Pitch" },
    { key = "r", label = "R Yaw" }
}

local function readPair(section, key)
    if type(section) ~= "table" then
        return nil, nil
    end

    local item = section[key]
    if type(item) == "table" then
        return item.current, item.target
    end

    local current = section.current and section.current[key]
    local target = section.target and section.target[key]
    return current, target
end

local function drawHeader(display, row, title)
    local width = display.getSize()
    core.writeAt(display, 1, row, title:sub(1, width), palette and palette.cyan)
    core.writeAt(display, 1, row + 1, "AXIS", palette and palette.gray)
    core.writeAt(display, 11, row + 1, "CUR", palette and palette.gray)
    core.writeAt(display, 23, row + 1, "TGT", palette and palette.gray)
end

local function drawRows(display, row, rows, section)
    local _, height = display.getSize()

    for _, spec in ipairs(rows) do
        if row > height - 1 then
            return row
        end

        local current, target = readPair(section, spec.key)
        local currentText = core.valueText(current)
        local targetText = core.valueText(target)

        core.writeAt(display, 1, row, spec.label, palette and palette.white)
        core.writeAt(display, 11, row, currentText, palette and palette.lime)
        core.writeAt(display, 23, row, targetText, palette and palette.yellow)
        row = row + 1
    end

    return row
end

function M.draw(display, state, status)
    state = state or {}
    core.clear(display)

    local width, height = display.getSize()
    local title = "AIRSHIP FC"
    core.writeAt(display, math.max(1, math.floor((width - #title) / 2) + 1), 1, title, palette and palette.cyan)

    local row = 3
    if row + 4 <= height then
        drawHeader(display, row, "ATTITUDE")
        row = drawRows(display, row + 2, attitudeRows, state.attitude)
        row = row + 1
    end

    if row + 4 <= height then
        drawHeader(display, row, "ATT RATE")
        row = drawRows(display, row + 2, rateRows, state.rates)
    end

    core.status(display, status)
end

return M
