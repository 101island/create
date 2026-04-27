local M = {}

function M.reply(sender, protocol, ok, value)
    rednet.send(sender, {
        ok = ok,
        value = value
    }, protocol)
end

function M.call(nodeID, protocol, target, method, args, timeout)
    rednet.send(nodeID, {
        target = target,
        method = method,
        args = args or {}
    }, protocol)

    local _, reply = rednet.receive(protocol, timeout or 1)
    return reply
end

function M.value(reply)
    if type(reply) ~= "table" then
        return nil, "No reply"
    end
    if not reply.ok then
        return nil, tostring(reply.value)
    end
    return reply.value
end

return M
