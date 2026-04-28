return {
    protocol = "aero_control",
    modemSide = "right",
    sensorOrder = { "forward", "down" },

    sensors = {
        forward = {
            side = "top",
            axis = "x",
            index = 1,
            scale = -1
        },
        down = {
            side = "left",
            axis = "y",
            index = 2,
            scale = 1
        }
    }
}
