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

local function itemText(item)
    if type(item) == "table" then
        return item.label or item.name or tostring(item[1])
    end
    return tostring(item)
end

function M.draw(display, items, active, row)
    row = row or 1

    local width = display.getSize()
    local x = 1

    for index, item in ipairs(items or {}) do
        local text = itemText(item)
        local selected = index == active
        local token = selected and ("[" .. text .. "]") or (" " .. text .. " ")

        if x + #token - 1 > width then
            break
        end

        core.setBackgroundColor(display, selected and palette and palette.white or palette and palette.black)
        core.writeAt(display, x, row, token, selected and palette and palette.black or palette and palette.white)
        core.setBackgroundColor(display, palette and palette.black)
        core.setTextColor(display, palette and palette.white)

        x = x + #token + 1
    end
end

function M.hitTest(items, x, y, row)
    row = row or 1
    if y ~= row then
        return nil
    end

    local cursor = 1
    for index, item in ipairs(items or {}) do
        local text = itemText(item)
        local tokenWidth = #text + 2

        if x >= cursor and x < cursor + tokenWidth then
            return index
        end

        cursor = cursor + tokenWidth + 1
    end

    return nil
end

return M
