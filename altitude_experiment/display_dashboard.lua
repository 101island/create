local runtimeState = dofile("runtime_state.lua")

local function loadDisplay(name)
    local path = "display/" .. name .. ".lua"
    local fn, err = loadfile(path)
    if not fn then
        error("Could not load display module [" .. name .. "]: " .. tostring(err), 0)
    end
    return fn()
end

local core = loadDisplay("core")
local device = loadDisplay("device")
local menu = loadDisplay("menu")
local plot = loadDisplay("plot")
local system = loadDisplay("system")

local M = {}

local palette = core.palette

local function numberText(value)
    local text = core.valueText(value)
    return text
end

local function modeText(runtime)
    if runtime.mode == "speed" then
        return "SPEED"
    end
    return "CASCADE"
end

local function drawValue(display, row, label, value, err, color)
    local text, valueErr = core.valueText(value, err)
    core.writeAt(display, 1, row, tostring(label):sub(1, 8), palette and palette.white)
    core.writeAt(display, 10, row, text, valueErr and palette and palette.red or color or palette and palette.lime)
    return row + 1
end

local function drawField(display, row, field, selected)
    local prefix = selected and ">" or " "
    local text = numberText(field.get())
    local labelColor = selected and palette and palette.yellow or palette and palette.white
    local valueColor = selected and palette and palette.yellow or palette and palette.lime

    core.writeAt(display, 1, row, prefix .. tostring(field.label):sub(1, 7), labelColor)
    core.writeAt(display, 10, row, text, valueColor)
    return row + 1
end

local function drawButtons(display, runtime)
    local width, height = display.getSize()
    local row = math.max(1, height - 1)
    local tokens = {
        { label = "[-]", action = "minus" },
        { label = "[+]", action = "plus" },
        { label = "[NEXT]", action = "next" },
        { label = runtime.enabled and "[OFF]" or "[ON]", action = "enable" },
        { label = "[" .. modeText(runtime) .. "]", action = "mode" }
    }

    local buttons = {}
    local x = 1
    for _, item in ipairs(tokens) do
        if x + #item.label - 1 <= width then
            core.writeAt(display, x, row, item.label, palette and palette.cyan)
            buttons[#buttons + 1] = {
                x1 = x,
                x2 = x + #item.label - 1,
                y = row,
                action = item.action
            }
            x = x + #item.label + 1
        end
    end

    return buttons
end

local function hitButton(buttons, x, y)
    for _, button in ipairs(buttons or {}) do
        if y == button.y and x >= button.x1 and x <= button.x2 then
            return button.action
        end
    end
    return nil
end

local function actuatorOutput(runtime)
    local commands = runtime.output and runtime.output.commands or {}
    local first = commands[1]
    if first then
        return first.output or first.command
    end
    return runtime.output and runtime.output.base or nil
end

local function innerFields(runtime)
    return {
        {
            label = "MAN SPD",
            get = function() return runtime.setpoints.speed end,
            step = 0.1,
            adjust = function(delta) runtimeState.adjustSetpoint(runtime, "speed", delta) end
        },
        {
            label = "KP",
            get = function() return runtime.innerPid.kp end,
            step = 0.1,
            adjust = function(delta) runtimeState.adjustPid(runtime, "inner", "kp", delta) end
        },
        {
            label = "KI",
            get = function() return runtime.innerPid.ki end,
            step = 0.01,
            adjust = function(delta) runtimeState.adjustPid(runtime, "inner", "ki", delta) end
        },
        {
            label = "KD",
            get = function() return runtime.innerPid.kd end,
            step = 0.01,
            adjust = function(delta) runtimeState.adjustPid(runtime, "inner", "kd", delta) end
        },
        {
            label = "BIAS",
            get = function() return runtime.innerPid.bias end,
            step = 0.5,
            adjust = function(delta) runtimeState.adjustPid(runtime, "inner", "bias", delta) end
        }
    }
end

local function outerFields(runtime)
    return {
        {
            label = "TGT ALT",
            get = function() return runtime.setpoints.altitude end,
            step = 1,
            adjust = function(delta) runtimeState.adjustSetpoint(runtime, "altitude", delta) end
        },
        {
            label = "KP",
            get = function() return runtime.outerPid.kp end,
            step = 0.1,
            adjust = function(delta) runtimeState.adjustPid(runtime, "outer", "kp", delta) end
        },
        {
            label = "KI",
            get = function() return runtime.outerPid.ki end,
            step = 0.01,
            adjust = function(delta) runtimeState.adjustPid(runtime, "outer", "ki", delta) end
        },
        {
            label = "KD",
            get = function() return runtime.outerPid.kd end,
            step = 0.01,
            adjust = function(delta) runtimeState.adjustPid(runtime, "outer", "kd", delta) end
        }
    }
end

local function buildSystemState(runtime)
    local sensorItems = {}
    local actuatorItems = {}
    local sensors = runtime.io and runtime.io.sensors or nil
    local actuators = runtime.io and runtime.io.actuators or nil

    if type(sensors) == "table" then
        local names = {}
        for key in pairs(sensors) do
            if key ~= "order" and not key:find("Err$") and not key:find("Method$") then
                names[#names + 1] = key
            end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            sensorItems[#sensorItems + 1] = {
                label = core.label(name),
                value = sensors[name],
                err = sensors[name .. "Err"]
            }
        end
    end

    if type(actuators) == "table" and type(actuators.order) == "table" then
        for _, alias in ipairs(actuators.order) do
            actuatorItems[#actuatorItems + 1] = {
                label = alias,
                value = actuators[alias],
                err = actuators[alias .. "Err"]
            }
        end
    end

    return {
        sensors = sensorItems,
        actuators = actuatorItems
    }
end

local function drawLoopPage(display, runtime, page, fields, selectedField, status)
    core.clear(display)

    local width, height = display.getSize()
    local title = page == "inner" and "INNER SPEED" or "OUTER ALT"
    core.writeAt(display, math.max(1, math.floor((width - #title) / 2) + 1), 1, title, palette and palette.cyan)

    local row = 3
    if page == "inner" then
        row = drawValue(display, row, "TGT SPD", runtime.speed.target, runtime.speed.err, palette and palette.yellow)
        row = drawValue(display, row, "CUR SPD", runtime.speed.current, runtime.speed.err, palette and palette.lime)
        row = drawValue(display, row, "ERR", runtime.speed.error, runtime.speed.err, palette and palette.orange)
        row = drawValue(display, row, "PID COR", runtime.output and runtime.output.correction, runtime.output and runtime.output.err, palette and palette.cyan)
        row = drawValue(display, row, "FF LVL", runtime.output and runtime.output.feedforward, runtime.output and runtime.output.feedforwardErr, palette and palette.yellow)
        row = drawValue(display, row, "OUT LVL", actuatorOutput(runtime), runtime.output and runtime.output.err, palette and palette.cyan)
        row = drawValue(display, row, "SEG", runtime.speed.pidSegment, nil, palette and palette.gray)
    else
        row = drawValue(display, row, "TGT ALT", runtime.position.target, runtime.position.err, palette and palette.yellow)
        row = drawValue(display, row, "CUR ALT", runtime.position.current, runtime.position.err, palette and palette.lime)
        row = drawValue(display, row, "ERR", runtime.position.error, runtime.position.err, palette and palette.orange)
        row = drawValue(display, row, "SPD TGT", runtime.position.output, runtime.position.err, palette and palette.cyan)
        row = drawValue(display, row, "SEG", runtime.position.pidSegment, nil, palette and palette.gray)
    end

    if row + #fields + 1 < height - 1 then
        row = row + 1
        core.writeAt(display, 1, row, "EDIT", palette and palette.gray)
        row = row + 1
    end

    local fieldRows = {}
    for index, field in ipairs(fields) do
        if row >= height - 1 then
            break
        end
        fieldRows[row] = index
        row = drawField(display, row, field, index == selectedField)
    end

    core.status(display, status)
    return fieldRows, drawButtons(display, runtime)
end

local function applyFieldDelta(fields, selectedField, sign)
    local field = fields[selectedField]
    if not field then
        return
    end
    local step = tonumber(field.step) or 1
    field.adjust(sign * step)
end

function M.run(runtime, options)
    options = options or {}

    local displayCfg = runtime.hardware.display or {}
    local side = options.side or displayCfg.side or "top"
    local period = tonumber(options.period) or runtime.displayPeriod
    local textScale = tonumber(options.textScale) or 0.5
    local remoteName = options.remoteName or displayCfg.remoteName
    local sample = options.sample == true

    local screen, screenErr = device.wrap(side, remoteName)
    if not screen then
        print("ERROR: " .. tostring(screenErr))
        return
    end

    core.configure(screen, textScale)

    local pages = {
        { label = "INR", key = "inner" },
        { label = "OUT", key = "outer" },
        { label = "PLT", key = "plot" },
        { label = "IO", key = "io" }
    }
    local active = 1
    local selected = {
        inner = 1,
        outer = 1
    }
    local fieldRows = {}
    local buttons = {}
    local status = tostring(side) .. (remoteName and ("->" .. remoteName) or "") .. "  " .. tostring(period) .. "s"

    if type(options.initialPage) == "string" then
        local requested = options.initialPage:upper()
        for index, page in ipairs(pages) do
            if page.label == requested then
                active = index
            end
        end
    end

    local function currentFields()
        local key = pages[active].key
        if key == "inner" then
            return innerFields(runtime), "inner"
        elseif key == "outer" then
            return outerFields(runtime), "outer"
        end
        return {}, key
    end

    local function refresh()
        if sample then
            runtimeState.step(runtime, { applyOutput = false })
        end

        local page = pages[active].key
        if page == "plot" then
            plot.draw(screen, runtime, status)
            menu.draw(screen, pages, active, 1)
            buttons = drawButtons(screen, runtime)
            fieldRows = {}
            return
        elseif page == "io" then
            system.draw(screen, buildSystemState(runtime), status)
            menu.draw(screen, pages, active, 1)
            buttons = drawButtons(screen, runtime)
            fieldRows = {}
            return
        end

        local fields, key = currentFields()
        fieldRows, buttons = drawLoopPage(screen, runtime, key, fields, selected[key] or 1, status)
        menu.draw(screen, pages, active, 1)
    end

    local function handleAction(action)
        local fields, key = currentFields()

        if action == "minus" then
            applyFieldDelta(fields, selected[key] or 1, -1)
        elseif action == "plus" then
            applyFieldDelta(fields, selected[key] or 1, 1)
        elseif action == "next" then
            if #fields > 0 then
                selected[key] = (selected[key] or 1) + 1
                if selected[key] > #fields then
                    selected[key] = 1
                end
            end
        elseif action == "enable" then
            runtimeState.toggleEnabled(runtime)
        elseif action == "mode" then
            runtimeState.toggleMode(runtime)
        end

        refresh()
    end

    refresh()

    if type(os.startTimer) ~= "function" or type(os.pullEvent) ~= "function" then
        while type(sleep) == "function" do
            sleep(period)
            refresh()
        end
        return
    end

    local timer = os.startTimer(period)
    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" and p1 == timer then
            refresh()
            timer = os.startTimer(period)
        elseif event == "monitor_touch" then
            local pageIndex = menu.hitTest(pages, p2, p3, 1)
            if pageIndex then
                active = pageIndex
                refresh()
            else
                local action = hitButton(buttons, p2, p3)
                if action then
                    handleAction(action)
                elseif fieldRows[p3] then
                    local _, key = currentFields()
                    selected[key] = fieldRows[p3]
                    refresh()
                end
            end
        elseif event == "mouse_click" then
            local pageIndex = menu.hitTest(pages, p2, p3, 1)
            if pageIndex then
                active = pageIndex
                refresh()
            else
                local action = hitButton(buttons, p2, p3)
                if action then
                    handleAction(action)
                elseif fieldRows[p3] then
                    local _, key = currentFields()
                    selected[key] = fieldRows[p3]
                    refresh()
                end
            end
        elseif event == "key" and keys then
            local fields, key = currentFields()
            if p1 == keys.left then
                active = active - 1
                if active < 1 then active = #pages end
                refresh()
            elseif p1 == keys.right then
                active = active + 1
                if active > #pages then active = 1 end
                refresh()
            elseif p1 == keys.up and #fields > 0 then
                selected[key] = (selected[key] or 1) - 1
                if selected[key] < 1 then selected[key] = #fields end
                refresh()
            elseif p1 == keys.down and #fields > 0 then
                selected[key] = (selected[key] or 1) + 1
                if selected[key] > #fields then selected[key] = 1 end
                refresh()
            elseif p1 == keys.minus then
                handleAction("minus")
            elseif p1 == keys.equals then
                handleAction("plus")
            elseif p1 == keys.space then
                handleAction("enable")
            elseif p1 == keys.m then
                handleAction("mode")
            elseif p1 == keys.r then
                runtimeState.reset(runtime)
                refresh()
            end
        end
    end
end

return M
