return {
    sensors = {
        down = {
            scale = -1
        }
    },

    sensorOrder = { "down" },

    altitude = {
        side = "right",
        scale = 1,
        bias = 0
    },

    display = {
        side = "top",
        remoteName = "monitor_0"
    },

    components = {
        TopThruster = {
            -- redstone_relay analog output: 0..15.
            -- Normal mapping: output = command * 1 + 0.
            -- Inverted 0..15 mapping: output = command * -1 + 15.
            peripheralType = "redstone_relay",
            outputSide = "left",
            scale = 1,
            bias = 0,
            outputMin = 0,
            outputMax = 15
        }
    }
}
