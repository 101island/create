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

function M.dataOrder(data)
    local order = data.order or {}
    if #order > 0 then
        return order
    end

    local names = {}
    for name in pairs(data) do
        if name ~= "nodeID" and name ~= "order" and not name:find("Err$") then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

function M.draw(display, data, status)
    if type(data) == "table" and type(data.metrics) == "table" then
        return M.drawMetrics(display, data, status)
    end

    core.clear(display)

    local width, height = display.getSize()
    local title = "AIRSPEED"
    local x = math.max(1, math.floor((width - #title) / 2) + 1)
    core.writeAt(display, x, 1, title, palette and palette.cyan)

    local row = 3
    for _, name in ipairs(M.dataOrder(data)) do
        if row > height - 1 then
            break
        end

        local text, err = core.valueText(data[name], data[name .. "Err"])
        local color = err and palette and palette.red or palette and palette.lime
        core.writeAt(display, 1, row, core.label(name), palette and palette.white)
        core.writeAt(display, math.max(10, math.floor(width / 2)), row, text, color)

        if err and row + 1 <= height - 1 then
            row = row + 1
            core.writeAt(display, 2, row, tostring(err):sub(1, width - 1), palette and palette.red)
        end

        row = row + 2
    end

    core.status(display, status)
end

function M.drawMetrics(display, data, status)
    core.clear(display)

    local width, height = display.getSize()
    local title = "AIRSPEED"
    local x = math.max(1, math.floor((width - #title) / 2) + 1)
    core.writeAt(display, x, 1, title, palette and palette.cyan)

    core.writeAt(display, 1, 3, "ITEM", palette and palette.gray)
    core.writeAt(display, 11, 3, "CUR", palette and palette.gray)
    core.writeAt(display, 23, 3, "TGT", palette and palette.gray)

    local row = 5
    for _, item in ipairs(data.metrics or {}) do
        if row > height - 1 then
            break
        end

        local currentText, currentErr = core.valueText(item.current, item.currentErr)
        local targetText = core.valueText(item.target)
        local currentColor = currentErr and palette and palette.red or palette and palette.lime

        core.writeAt(display, 1, row, item.label or core.label(item.key or "item"), palette and palette.white)
        core.writeAt(display, 11, row, currentText, currentColor)
        core.writeAt(display, 23, row, targetText, palette and palette.yellow)

        if currentErr and row + 1 <= height - 1 then
            row = row + 1
            core.writeAt(display, 2, row, tostring(currentErr):sub(1, width - 1), palette and palette.red)
        end

        row = row + 2
    end

    core.status(display, status)
end

function M.drawError(display, message, status)
    core.clear(display)

    local width, height = display.getSize()
    if height >= 1 then
        core.writeAt(display, 1, 1, "AIRSPEED", palette and palette.cyan)
    end
    if height >= 3 then
        core.writeAt(display, 1, 3, "ERROR", palette and palette.red)
    end
    if height >= 5 then
        core.writeAt(display, 1, 5, tostring(message):sub(1, width), palette and palette.red)
    end

    core.status(display, status)
end

return M
