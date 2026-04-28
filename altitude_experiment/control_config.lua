return {
    altitudeExperiment = {
        enabled = true,
        -- cascade: altitude PID generates speed target.
        -- speed: inner speed PID uses speedSetpoint directly.
        mode = "cascade",
        period = 0.2,
        displayPeriod = 0.5,
        plotHistory = 120,
        feedforward = {
            enabled = true,
            -- target = use target altitude, matching the reference script's hover_fill(target).
            -- current = use current measured altitude.
            source = "target",
            -- Calibration point from the referenced pid.lua.
            referenceAltitude = 205,
            referenceLevel = 7,
            capacity = 122,
            maxSteamOutput = 200,
            outputMin = 0,
            outputMax = 15,
            pressure = {
                seaLevel = 63,
                minY = -64,
                logicalHeight = 704,
                baseSlope = -0.004,
                maxPressure = 1.5,
                maxStep = 200,
                smoothingMargin = 40
            }
        },
        -- Target height for cascade mode.
        positionSetpoint = 0,
        -- Manual speed target for speed mode.
        speedSetpoint = 0,
        -- Maximum output change per control step.
        maxStep = 1,
        positionMeasurement = {
            field = "altitude",
            scale = 1
        },
        speedMeasurement = {
            field = "down",
            scale = -1
        },
        outputs = {
            {
                alias = "TopThruster",
                ratio = 1
            }
        },
        outerPid = {
            kp = 0.3,
            ki = 0.03,
            kd = 0.01,
            bias = 0,
            outputMin = -20,
            outputMax = 20,
            integralMin = -20,
            integralMax = 20,
            -- Altitude-based gain schedule. Add kp/ki/kd/output limits inside
            -- a segment only after that altitude band has measured tuning data.
            segments = {
                { name = "low", altitudeMax = 128 },
                { name = "mid", altitudeMin = 128, altitudeMax = 256 },
                { name = "high", altitudeMin = 256 }
            }
        },
        innerPid = {
            kp = 0.3,
            ki = 0.02,
            kd = 0.01,
            -- Inner PID output is a signed correction added on top of feedforward.
            bias = 0,
            outputMin = -7,
            outputMax = 7,
            integralMin = -15,
            integralMax = 15,
            segments = {
                { name = "low", altitudeMax = 128 },
                { name = "mid", altitudeMin = 128, altitudeMax = 256 },
                { name = "high", altitudeMin = 256 }
            }
        },
        stopOnSensorError = true
    }
}
