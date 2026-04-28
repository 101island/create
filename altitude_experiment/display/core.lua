local M = {}

M.palette = type(colors) == "table" and colors or nil

function M.setTextColor(display, color)
    if M.palette and color and type(display.setTextColor) == "function" then
        display.setTextColor(color)
    end
end

function M.setBackgroundColor(display, color)
    if M.palette and color and type(display.setBackgroundColor) == "function" then
        display.setBackgroundColor(color)
    end
end

function M.writeAt(display, x, y, text, color)
    display.setCursorPos(x, y)
    M.setTextColor(display, color)
    display.write(tostring(text))
end

function M.label(name)
    return name:sub(1, 1):upper() .. name:sub(2)
end

function M.configure(display, scale)
    if type(display.setTextScale) == "function" and scale then
        pcall(function()
            display.setTextScale(scale)
        end)
    end
end

function M.clear(display)
    M.setBackgroundColor(display, M.palette and M.palette.black)
    M.setTextColor(display, M.palette and M.palette.white)
    display.clear()
    display.setCursorPos(1, 1)
end

function M.valueText(value, err)
    if value == nil then
        return "--", err
    end
    if type(value) == "number" then
        return string.format("%.2f", value), nil
    end
    return tostring(value), nil
end

function M.status(display, text)
    if not text then
        return
    end

    local width, height = display.getSize()
    if height >= 1 then
        M.writeAt(display, 1, height, tostring(text):sub(1, width), M.palette and M.palette.gray)
    end
end

return M
