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

local function drawPairs(display, row, items)
    local _, height = display.getSize()

    for _, item in ipairs(items or {}) do
        if row > height - 1 then
            return row
        end

        local text, err = core.valueText(item.value, item.err)
        local color = err and palette and palette.red or item.color or palette and palette.lime

        core.writeAt(display, 1, row, tostring(item.label):sub(1, 8), palette and palette.white)
        core.writeAt(display, 10, row, text, color)
        row = row + 1
    end

    return row
end

function M.draw(display, state, status)
    state = state or {}
    core.clear(display)

    local width, height = display.getSize()
    local title = tostring(state.title or "LOOP")
    core.writeAt(display, math.max(1, math.floor((width - #title) / 2) + 1), 1, title, palette and palette.cyan)

    local row = 3
    row = drawPairs(display, row, state.values)

    if row + 1 <= height - 1 then
        row = row + 1
        core.writeAt(display, 1, row, "PID", palette and palette.gray)
        row = row + 1
        row = drawPairs(display, row, state.params)
    end

    core.status(display, status)
end

return M
