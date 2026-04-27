return {
    protocol = "aero_control",
    modemSide = "right",

    sensors = {
        forward = {
            side = "bottom",
            axis = "x",
            index = 1,
            aliases = { "bottom", "forward" }
        },
        vertical = {
            side = "left",
            axis = "y",
            index = 2,
            aliases = { "left", "back", "vertical" }
        }
    }
}
