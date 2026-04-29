local M = {}

local columns = {
    "t",
    "mode",
    "enabled",
    "target_altitude",
    "altitude",
    "altitude_error",
    "target_speed",
    "speed",
    "speed_error",
    "output_command",
    "actuator_output",
    "feedforward",
    "correction",
    "pressure",
    "inner_segment",
    "outer_segment",
    "status"
}

local function nowSeconds()
    if type(os) == "table" and type(os.epoch) == "function" then
        return os.epoch("utc") / 1000
    end
    if type(os) == "table" and type(os.clock) == "function" then
        return os.clock()
    end
    return 0
end

local function csvValue(value)
    if value == nil then
        return ""
    end
    if type(value) == "boolean" then
        return value and "1" or "0"
    end
    if type(value) == "number" then
        return tostring(value)
    end

    local text = tostring(value)
    if text:find("[,\"]") or text:find("\n") or text:find("\r") then
        text = text:gsub("\"", "\"\"")
        return "\"" .. text .. "\""
    end
    return text
end

local function joinCsv(values)
    local out = {}
    for index, value in ipairs(values) do
        out[index] = csvValue(value)
    end
    return table.concat(out, ",")
end

local function fsExists(path)
    if type(fs) == "table" and type(fs.exists) == "function" then
        return fs.exists(path)
    end
    local file = io and io.open and io.open(path, "r") or nil
    if file then
        file:close()
        return true
    end
    return false
end

local function fsSize(path)
    if type(fs) == "table" and type(fs.getSize) == "function" then
        return fs.getSize(path)
    end
    local file = io and io.open and io.open(path, "r") or nil
    if not file then
        return 0
    end
    local size = file:seek("end")
    file:close()
    return size or 0
end

local function ensureDir(path)
    if type(fs) ~= "table" or type(fs.getDir) ~= "function" or type(fs.makeDir) ~= "function" then
        return
    end

    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

local function appendLine(path, line)
    ensureDir(path)

    if type(fs) == "table" and type(fs.open) == "function" then
        local handle = fs.open(path, "a")
        if not handle then
            return nil, "Could not open log file [" .. tostring(path) .. "]"
        end
        handle.writeLine(line)
        handle.close()
        return true
    end

    if type(io) == "table" and type(io.open) == "function" then
        local handle, err = io.open(path, "a")
        if not handle then
            return nil, err
        end
        handle:write(line .. "\n")
        handle:close()
        return true
    end

    return nil, "No file API available"
end

local function firstCommand(runtime)
    local commands = runtime.output and runtime.output.commands or nil
    if type(commands) == "table" then
        return commands[1]
    end
    return nil
end

local function row(runtime)
    local command = firstCommand(runtime) or {}

    return {
        nowSeconds(),
        runtime.mode,
        runtime.enabled,
        runtime.position and runtime.position.target,
        runtime.position and runtime.position.current,
        runtime.position and runtime.position.error,
        runtime.speed and runtime.speed.target,
        runtime.speed and runtime.speed.current,
        runtime.speed and runtime.speed.error,
        runtime.output and runtime.output.base,
        command.output or command.command,
        runtime.output and runtime.output.feedforward,
        runtime.output and runtime.output.correction,
        runtime.output and runtime.output.pressure,
        runtime.output and runtime.output.innerSegment,
        runtime.output and runtime.output.outerSegment,
        runtime.status
    }
end

function M.new(cfg, overrides)
    cfg = cfg or {}
    overrides = overrides or {}

    local path = overrides.path or cfg.path or "altitude_log.csv"
    local logger = {
        enabled = overrides.enabled,
        path = path,
        decimation = tonumber(overrides.decimation or cfg.decimation) or 1,
        count = 0
    }

    if logger.enabled == nil then
        logger.enabled = cfg.enabled == true
    end

    if logger.enabled and (not fsExists(path) or fsSize(path) == 0) then
        local ok, err = appendLine(path, table.concat(columns, ","))
        if not ok then
            logger.enabled = false
            logger.err = err
        end
    end

    return logger
end

function M.write(logger, runtime)
    if type(logger) ~= "table" or not logger.enabled then
        return true
    end

    logger.count = logger.count + 1
    if logger.decimation > 1 and ((logger.count - 1) % logger.decimation) ~= 0 then
        return true
    end

    return appendLine(logger.path, joinCsv(row(runtime)))
end

return M
