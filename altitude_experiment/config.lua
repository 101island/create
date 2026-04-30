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
        remoteName = "monitor_1"
    },

    -- Fractional actuator commands are emitted by a fixed-rate PDM/PWM
    -- service. 0.05 s is one Minecraft tick at 20 TPS.
    actuatorPwm = {
        enabled = true,
        period = 0.05
    },

    components = {
        TopThruster = {
            -- redstone_relay analog output: 0..15.
            -- Normal mapping: output = command * 1 + 0.
            -- Inverted 0..15 mapping: output = command * -1 + 15.
            peripheralType = "redstone_relay",
            -- Fill this with the exact wired peripheral name if multiple
            -- redstone relays exist, for example "redstone_relay_0".
            remoteName = "redstone_relay_0",
            outputSide = "left",
            scale = 1,
            bias = 0,
            outputMin = 0,
            outputMax = 15
        }
    }
}
