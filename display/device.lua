local M = {}

local requiredMethods = {
    "clear",
    "setCursorPos",
    "write",
    "getSize"
}

function M.wrap(side)
    if type(peripheral) ~= "table" or type(peripheral.wrap) ~= "function" then
        return nil, "peripheral.wrap() is not available in this runtime"
    end

    local display = peripheral.wrap(side)
    if not display then
        return nil, "No display on " .. tostring(side)
    end

    for _, method in ipairs(requiredMethods) do
        if type(display[method]) ~= "function" then
            return nil, "Peripheral on " .. tostring(side) .. " is not a text display"
        end
    end

    return display
end

return M
