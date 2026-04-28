local client = dofile("client.lua")
local args = {...}

local function printTable(title, data)
    print(title)
    if type(data) ~= "table" then
        print("  nil")
        return
    end

    local names = {}
    for key in pairs(data) do
        if key ~= "order" and not key:find("Err$") and not key:find("Method$") then
            names[#names + 1] = key
        end
    end
    table.sort(names)

    for _, name in ipairs(names) do
        local value = data[name]
        local err = data[name .. "Err"]
        local method = data[name .. "Method"]
        local line = "  " .. tostring(name) .. " = " .. tostring(value)
        if method then
            line = line .. "  (" .. tostring(method) .. ")"
        end
        if err then
            line = line .. "  ERR=" .. tostring(err)
        end
        print(line)
    end
end

local period = tonumber(args[1])

local function draw()
    if term and term.clear then
        term.clear()
    end
    if term and term.setCursorPos then
        term.setCursorPos(1, 1)
    end

    local io = client.readIO()
    local sensors = io and io.sensors or nil
    local actuators = io and io.actuators or nil

    printTable("SENSORS", sensors)
    printTable("ACTUATORS", actuators)
end

if period and period > 0 then
    while true do
        draw()
        sleep(period)
    end
else
    draw()
end
