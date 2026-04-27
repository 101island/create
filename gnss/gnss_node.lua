local cfg = dofile("config.lua")
local rpc = dofile("rpc.lua")
local gnss = dofile("gnss.lua")

rednet.open(cfg.modemSide)

print("GNSS node online")
print("ID: " .. os.getComputerID())
print("Role: " .. tostring(gnss.role(cfg)))
print("Timeout: " .. tostring(cfg.timeout))

local function collectSlaveFixes()
    local fixes = {}
    local errors = {}
    local role = gnss.role(cfg)

    if gnss.useLocal(cfg) then
        local localFix, localErr = gnss.localFix(cfg)
        if localFix then
            fixes[#fixes + 1] = localFix
        elseif localErr then
            errors[#errors + 1] = "local=" .. tostring(localErr)
        end
    end

    if role ~= "master" then
        return fixes, errors
    end

    for _, nodeID in ipairs(cfg.slaveIDs or {}) do
        local reply = rpc.call(nodeID, cfg.protocol, "gnss", "readLocal", {}, cfg.rpcTimeout or 5)
        local value, err = rpc.value(reply)
        if type(value) == "table" then
            fixes[#fixes + 1] = value
        else
            errors[#errors + 1] = tostring(nodeID) .. "=" .. tostring(err)
        end
    end

    return fixes, errors
end

local function solveFix()
    local role = gnss.role(cfg)
    if role ~= "master" then
        return gnss.readAll(cfg)
    end

    local fixes, errors = collectSlaveFixes()
    local result, err = gnss.averageFixes(cfg, fixes)
    if not result then
        if #errors > 0 then
            return nil, table.concat(errors, "; ")
        end
        return nil, err
    end

    if #errors > 0 then
        result.partial = true
        result.partialErr = table.concat(errors, "; ")
    end

    return result
end

local function solveField(fieldName)
    local role = gnss.role(cfg)
    if role ~= "master" then
        return gnss.readLocal(cfg, fieldName)
    end

    local result, err = solveFix()
    if not result then
        return nil, err
    end

    local value = result[fieldName]
    if value == nil then
        return nil, "Unknown field [" .. tostring(fieldName) .. "]"
    end

    return value
end

while true do
    local sender, msg = rednet.receive(cfg.protocol)

    if type(msg) == "table" and msg.method == "readAll" then
        local result, err = solveFix()
        rpc.reply(sender, cfg.protocol, result ~= nil, result or err)
    elseif type(msg) == "table" and msg.method == "readLocal" then
        local result, err = gnss.readAll(cfg)
        rpc.reply(sender, cfg.protocol, result ~= nil, result or err)
    elseif type(msg) == "table" and msg.method ~= "get" then
        rpc.reply(sender, cfg.protocol, false, "Unsupported method: " .. tostring(msg.method))
    else
        local fieldName, targetErr = gnss.resolveTarget(cfg, msg)

        if fieldName then
            local value, err = solveField(fieldName)
            rpc.reply(sender, cfg.protocol, value ~= nil, value or err)
        else
            rpc.reply(sender, cfg.protocol, false, targetErr)
        end
    end
end
