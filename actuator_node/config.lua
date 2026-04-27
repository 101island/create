return {
    -- rednet protocol name. Keep this the same as control_hub/config.lua.
    protocol = "aero_control",

    -- Side where the wireless modem is attached.
    -- Fill in: "left" / "right" / "top" / "bottom" / "front" / "back"
    modemSide = "right",

    components = {
        -- Request name used by the control hub.
        -- Keep this key equal to control_hub/config.lua -> nodes entry name.
        --
        -- Fill in the peripheral side of the motor:
        -- "left" / "right" / "top" / "bottom" / "front" / "back"
        MainThruster = "back"
    }
}
