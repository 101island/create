local M = {}

local defaultFieldOrder = { "x", "y", "z", "altitude" }

function M.fieldNames(cfg)
    local names = {}

    if type(cfg.fieldOrder) == "table" then
        for _, name in ipairs(cfg.fieldOrder) do
            names[#names + 1] = name
        end
    end

    if #names == 0 then
        for _, name in ipairs(defaultFieldOrder) do
            names[#names + 1] = name
        end
    end

    return names
end

function M.role(cfg)
    local role = cfg and cfg.role or "slave"
    if role ~= "master" then
        return "slave"
    end
    return role
end

function M.useLocal(cfg)
    return cfg == nil or cfg.useLocal ~= false
end

function M.resolveTarget(cfg, msg)
    local target = msg
    if type(msg) == "table" then
        target = msg.target
    end

    if type(target) ~= "string" then
        return nil, "Unknown target [" .. tostring(target) .. "]"
    end

    for _, name in ipairs(M.fieldNames(cfg)) do
        if name == target then
            return target
        end
    end

    return nil, "Unknown target [" .. tostring(target) .. "]"
end

function M.locate(cfg)
    if type(gps) ~= "table" or type(gps.locate) ~= "function" then
        return nil, "gps.locate() is not available in this runtime"
    end

    local timeout = tonumber(cfg.timeout) or 2
    local x, y, z = gps.locate(timeout)
    if x == nil or y == nil or z == nil then
        return nil, "gps.locate() failed"
    end

    return {
        x = x,
        y = y,
        z = z,
        altitude = y,
        source = "local"
    }
end

function M.localFix(cfg)
    return M.locate(cfg)
end

function M.readLocal(cfg, fieldName)
    local fix, err = M.localFix(cfg)
    if not fix then
        return nil, err
    end

    local value = fix[fieldName]
    if value == nil then
        return nil, "Unknown field [" .. tostring(fieldName) .. "]"
    end

    return value
end

function M.averageFixes(cfg, fixes)
    local count = 0
    local sums = {}
    local result = {
        order = M.fieldNames(cfg)
    }

    for _, fix in ipairs(fixes or {}) do
        if type(fix) == "table" then
            count = count + 1
            for _, name in ipairs(result.order) do
                local value = fix[name]
                if type(value) == "number" then
                    sums[name] = (sums[name] or 0) + value
                end
            end
        end
    end

    if count == 0 then
        return nil, "No GNSS fixes"
    end

    for _, name in ipairs(result.order) do
        if type(sums[name]) == "number" then
            result[name] = sums[name] / count
        end
    end

    result.sourceCount = count
    return result
end

function M.read(cfg, fieldName)
    local fix, err = M.readAll(cfg)
    if not fix then
        return nil, err
    end

    local value = fix[fieldName]
    if value == nil then
        return nil, "Unknown field [" .. tostring(fieldName) .. "]"
    end

    return value
end

function M.readAll(cfg)
    local fix, err = M.localFix(cfg)
    if not fix then
        return nil, err
    end

    local result = {
        order = M.fieldNames(cfg)
    }

    for _, name in ipairs(result.order) do
        result[name] = fix[name]
    end

    return result
end

return M
