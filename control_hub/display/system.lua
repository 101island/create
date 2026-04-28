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

local function drawSectionHeader(display, row, title)
    core.writeAt(display, 1, row, title, palette and palette.cyan)
    core.writeAt(display, 1, row + 1, "ITEM", palette and palette.gray)
    core.writeAt(display, 18, row + 1, "VAL", palette and palette.gray)
end

local function drawRows(display, row, items)
    local width, height = display.getSize()

    for _, item in ipairs(items or {}) do
        if row > height - 1 then
            return row
        end

        local valueText, valueErr = core.valueText(item.value, item.err)
        local valueColor = valueErr and palette and palette.red or palette and palette.lime

        core.writeAt(display, 1, row, tostring(item.label):sub(1, 16), palette and palette.white)
        core.writeAt(display, 18, row, valueText, valueColor)

        if valueErr and row + 1 <= height - 1 then
            row = row + 1
            core.writeAt(display, 2, row, tostring(valueErr):sub(1, width - 1), palette and palette.red)
        end

        row = row + 1
    end

    return row
end

function M.draw(display, state, status)
    state = state or {}
    core.clear(display)

    local width, height = display.getSize()
    local title = "SYSTEM IO"
    core.writeAt(display, math.max(1, math.floor((width - #title) / 2) + 1), 1, title, palette and palette.cyan)

    local row = 3
    if row + 3 <= height then
        drawSectionHeader(display, row, "SENSORS")
        row = drawRows(display, row + 2, state.sensors) + 1
    end

    if row + 3 <= height then
        drawSectionHeader(display, row, "ACTUATORS")
        row = drawRows(display, row + 2, state.actuators)
    end

    core.status(display, status)
end

return M
