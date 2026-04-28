local M = {}
local altitude = dofile("altitude.lua")

local lastHeight = nil
local lastTime = nil

local function nowSeconds()
    if type(os) == "table" and type(os.clock) == "function" then
        return os.clock()
    end
    if type(os) == "table" and type(os.epoch) == "function" then
        return os.epoch("ingame") / 72000
    end
    return 0
end

function M.sensorNames(cfg)
    local names = {}

    if type(cfg.sensorOrder) == "table" then
        for _, name in ipairs(cfg.sensorOrder) do
            if cfg.sensors and cfg.sensors[name] then
                names[#names + 1] = name
            end
        end
        return names
    end

    for name in pairs(cfg.sensors or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function M.read(cfg, sensorName, currentHeight)
    local spec = cfg.sensors and cfg.sensors[sensorName]
    if not spec then
        return nil, "Unknown sensor [" .. tostring(sensorName) .. "]"
    end

    local height = currentHeight
    if height == nil then
        local err
        height, err = altitude.read(cfg)
        if height == nil then
            return nil, err
        end
    end

    local now = nowSeconds()
    local value = 0
    if lastHeight ~= nil and lastTime ~= nil then
        local dt = now - lastTime
        if dt > 0 then
            value = (height - lastHeight) / dt
        end
    end

    lastHeight = height
    lastTime = now

    local scale = tonumber(spec.scale) or 1
    return value * scale
end

function M.readAll(cfg, currentHeight, heightErr)
    local result = {
        order = M.sensorNames(cfg)
    }

    for _, name in ipairs(result.order) do
        local value, err
        if heightErr then
            value = nil
            err = heightErr
        else
            value, err = M.read(cfg, name, currentHeight)
        end
        result[name] = value
        if err then
            result[name .. "Err"] = err
        end
    end

    return result
end

return M
