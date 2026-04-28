local M = {}

local requiredMethods = {
    "clear",
    "setCursorPos",
    "write",
    "getSize"
}

local function validateDisplay(display, source)
    for _, method in ipairs(requiredMethods) do
        if type(display[method]) ~= "function" then
            return nil, "Peripheral on " .. tostring(source) .. " is not a text display"
        end
    end
    return display
end

function M.wrap(side, remoteName)
    if type(peripheral) ~= "table" then
        return nil, "peripheral API is not available in this runtime"
    end

    if (remoteName == nil or remoteName == "") and type(peripheral.find) == "function" then
        local found = peripheral.find("monitor")
        if found then
            return validateDisplay(found, "monitor")
        end
    end

    if type(peripheral.wrap) ~= "function" then
        return nil, "peripheral.wrap() is not available in this runtime"
    end

    local wrapped = peripheral.wrap(side)
    if not wrapped then
        return nil, "No peripheral on " .. tostring(side)
    end

    if type(remoteName) == "string" and remoteName ~= "" then
        if type(wrapped.callRemote) ~= "function" then
            return nil, "Peripheral on " .. tostring(side) .. " has no callRemote"
        end

        local proxy = {}
        for _, method in ipairs(requiredMethods) do
            proxy[method] = function(...)
                return wrapped.callRemote(remoteName, method, ...)
            end
        end

        local extraMethods = {
            "setTextScale",
            "setTextColor",
            "setBackgroundColor"
        }
        for _, method in ipairs(extraMethods) do
            proxy[method] = function(...)
                return wrapped.callRemote(remoteName, method, ...)
            end
        end

        return validateDisplay(proxy, tostring(side) .. "->" .. tostring(remoteName))
    end

    return validateDisplay(wrapped, side)
end

return M
