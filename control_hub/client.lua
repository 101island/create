local M = {}

local cfg = dofile("config.lua")
local rpc = dofile("rpc.lua")

function M.config()
    return cfg
end

function M.open()
    rednet.open(cfg.modemSide)
end

function M.nodeID(nodeName)
    local nodeID = cfg.nodes and cfg.nodes[nodeName]
    if not nodeID then
        return nil, "Unknown node [" .. tostring(nodeName) .. "]"
    end
    return nodeID
end

function M.call(nodeID, target, method, args, timeout)
    M.open()

    local reply = rpc.call(nodeID, cfg.protocol, target, method, args, timeout)
    return rpc.value(reply)
end

function M.setSpeed(nodeID, alias, rpm)
    return M.call(nodeID, alias, "setSpeed", { rpm }, 5)
end

function M.setNodeSpeed(nodeName, alias, rpm)
    local nodeID, err = M.nodeID(nodeName)
    if not nodeID then
        return nil, err
    end

    return M.setSpeed(nodeID, alias or nodeName, rpm)
end

function M.readAirspeed()
    local nodeID, err = M.nodeID("Airspeed")
    if not nodeID then
        return nil, err
    end

    local result, readErr = M.call(nodeID, "airspeed", "readAll", {}, 5)
    if type(result) ~= "table" then
        return nil, readErr
    end

    result.nodeID = nodeID
    return result
end

function M.readGnss()
    local nodeID, err = M.nodeID("GNSS")
    if not nodeID then
        return nil, err
    end

    local result, readErr = M.call(nodeID, "gnss", "readAll", {}, 5)
    if type(result) ~= "table" then
        return nil, readErr
    end

    result.nodeID = nodeID
    return result
end

function M.readActuatorNode(nodeName)
    local nodeID, err = M.nodeID(nodeName)
    if not nodeID then
        return nil, err
    end

    local result, readErr = M.call(nodeID, "actuator", "readAll", {}, 5)
    if type(result) ~= "table" then
        return nil, readErr
    end

    result.nodeID = nodeID
    result.nodeName = nodeName
    return result
end

return M
