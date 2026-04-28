local args = {...}
local command = args[1]
local runtimeState = dofile("runtime_state.lua")
local dashboard = dofile("display_dashboard.lua")

local function usage()
    print("Usage:")
    print("display.lua dashboard [side] [period] [scale] [remoteName]")
    print("display.lua io [side] [period] [scale] [remoteName]")
end

local function tail(startIndex)
    local result = {}
    for i = startIndex, #args do
        result[#result + 1] = args[i]
    end
    return result
end

local function runDashboard(arguments, initialPage, enabled)
    local runtime = runtimeState.new({
        enabled = enabled
    })

    dashboard.run(runtime, {
        side = arguments[1],
        period = tonumber(arguments[2]),
        textScale = tonumber(arguments[3]),
        remoteName = arguments[4],
        initialPage = initialPage or arguments[5],
        sample = true
    })
end

if not command then
    usage()
elseif command == "dashboard" then
    runDashboard(tail(2), nil, false)
elseif command == "io" then
    runDashboard(tail(2), "IO", false)
else
    print("ERROR: Unknown display command [" .. tostring(command) .. "]")
    usage()
end
