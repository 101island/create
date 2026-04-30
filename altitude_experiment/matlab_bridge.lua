local args = { ... }

local cfg = dofile("config.lua")
local io = dofile("io.lua")
local actuator = dofile("actuator.lua")

local url = args[1] or "ws://127.0.0.1:8768/cc"
local period = tonumber(args[2]) or 0.2
local defaultAlias = args[3] or "TopThruster"
local token = args[4] or ""
local stopOnExit = args[5] ~= "--no-stop"

local encode = textutils and (textutils.serializeJSON or textutils.serialiseJSON)
local decode = textutils and (textutils.unserializeJSON or textutils.unserialiseJSON)

local commandStats = {
    received = 0,
    ok = 0,
    failed = 0,
    lastId = nil,
    lastOp = nil,
    lastErr = nil,
    lastResult = nil
}

local function nowSeconds()
    if type(os.epoch) == "function" then
        return os.epoch("utc") / 1000
    end
    return os.clock()
end

local function send(ws, value)
    if type(encode) ~= "function" then
        return nil, "textutils JSON support is not available"
    end
    ws.send(encode(value))
    return true
end

local function readSensors()
    local ok, result = pcall(function()
        return io.readAll(cfg)
    end)
    if ok then
        return result
    end
    return {
        sensors = { err = tostring(result) },
        actuators = {}
    }
end

local function sendState(ws, status)
    local snapshot = readSensors()
    return send(ws, {
        type = "state",
        computerID = os.getComputerID and os.getComputerID() or nil,
        t = nowSeconds(),
        sensors = snapshot.sensors,
        actuators = snapshot.actuators,
        bridge = {
            commands = commandStats
        },
        status = status or "ok"
    })
end

local function ack(ws, command, ok, result, err)
    commandStats.received = commandStats.received + 1
    commandStats.lastId = command and command.id
    commandStats.lastOp = command and command.type
    commandStats.lastErr = err
    commandStats.lastResult = result
    if ok == true then
        commandStats.ok = commandStats.ok + 1
    else
        commandStats.failed = commandStats.failed + 1
    end

    return send(ws, {
        type = "ack",
        id = command and command.id,
        op = command and command.type,
        ok = ok == true,
        result = result,
        err = err
    })
end

local function handleCommand(ws, command)
    if type(command) ~= "table" then
        ack(ws, {}, false, nil, "Invalid command")
        return
    end

    if command.type == "ping" then
        ack(ws, command, true, { t = nowSeconds() }, nil)
        return
    end

    if command.type == "set_output" or command.type == "stop" then
        local alias = command.alias or defaultAlias
        local value = command.type == "stop" and 0 or tonumber(command.command)
        if value == nil then
            ack(ws, command, false, nil, "Invalid actuator command")
            return
        end

        local result, err = actuator.setOutput(cfg, alias, value)
        if result then
            ack(ws, command, true, result, nil)
        else
            ack(ws, command, false, nil, err)
        end
        return
    end

    if command.type == "set_height" then
        ack(ws, command, false, nil, "Direct height write is not supported by current Lua/peripheral APIs")
        return
    end

    ack(ws, command, false, nil, "Unknown command type [" .. tostring(command.type) .. "]")
end

if type(http) ~= "table" or type(http.websocket) ~= "function" then
    print("ERROR: http.websocket is not available. Enable ComputerCraft HTTP/WebSocket.")
    return
end

if type(encode) ~= "function" or type(decode) ~= "function" then
    print("ERROR: textutils JSON functions are not available.")
    return
end

if token ~= "" and not url:find("[?&]token=", 1, false) then
    local sep = url:find("?", 1, false) and "&" or "?"
    url = url .. sep .. "token=" .. token
end

local headers = nil
if token ~= "" then
    headers = {
        ["X-Bridge-Token"] = token
    }
end

local displayUrl = url:gsub("([?&]token=)[^&]+", "%1***")
print("MATLAB bridge")
print("ws=" .. tostring(displayUrl))
print("period=" .. tostring(period) .. " alias=" .. tostring(defaultAlias))
print("loop=websocket_receive")
print("auth=" .. (token ~= "" and "token" or "none"))

local ws, err = http.websocket(url, headers)
if not ws then
    print("ERROR: " .. tostring(err))
    return
end

send(ws, {
    type = "hello",
    computerID = os.getComputerID and os.getComputerID() or nil,
    alias = defaultAlias,
    period = period
})

local function bridgeLoop()
    local nextStateAt = nowSeconds()
    while true do
        local timeout = nextStateAt - nowSeconds()
        if timeout < 0 then
            timeout = 0
        end

        local message = ws.receive(timeout)
        if message then
            local command
            if type(decode) == "function" then
                local ok, parsed = pcall(function()
                    return decode(message)
                end)
                if ok then
                    command = parsed
                end
            end

            if command then
                handleCommand(ws, command)
            else
                ack(ws, {}, false, nil, "Invalid JSON command")
            end
        end

        local current = nowSeconds()
        if current >= nextStateAt then
            sendState(ws)
            repeat
                nextStateAt = nextStateAt + period
            until nextStateAt > current
        end
    end
end

local function pwmLoop()
    actuator.runPwm(cfg)
end

local ok, loopErr
if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
    ok, loopErr = pcall(function()
        parallel.waitForAny(bridgeLoop, pwmLoop)
    end)
else
    print("WARN: parallel.waitForAny is unavailable; fractional actuator PWM will not refresh independently.")
    ok, loopErr = pcall(bridgeLoop)
end

if stopOnExit then
    actuator.setOutput(cfg, defaultAlias, 0)
    actuator.update(cfg, defaultAlias, true)
end

pcall(function()
    ws.close()
end)

if not ok then
    print("Bridge stopped: " .. tostring(loopErr))
end
