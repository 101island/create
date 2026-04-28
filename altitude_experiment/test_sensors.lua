local client = dofile("client.lua")

while true do
    if term and term.clear then term.clear() end
    if term and term.setCursorPos then term.setCursorPos(1, 1) end

    local io = client.readIO()
    local sensors = io and io.sensors or {}
    local actuators = io and io.actuators or {}

    print("=== SENSORS ===")
    print("down     =", sensors.down, sensors.downErr)
    print("altitude =", sensors.altitude, sensors.altitudeErr)

    print("")
    print("=== ACTUATORS ===")
    if type(actuators.order) == "table" then
        for _, name in ipairs(actuators.order) do
            print(name, "=", actuators[name], actuators[name .. "Err"])
        end
    else
        print("no actuator order")
    end

    sleep(0.2)
end
