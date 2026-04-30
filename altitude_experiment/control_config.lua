return {
    altitudeExperiment = {
        enabled = true,
        -- cascade: altitude PID generates speed target.
        -- speed: inner speed PID uses speedSetpoint directly.
        mode = "cascade",
        period = 0.2,
        displayPeriod = 0.5,
        plotHistory = 120,
        logging = {
            enabled = false,
            path = "altitude_log.csv",
            decimation = 1
        },
        feedforward = {
            enabled = true,
            -- current = use current measured altitude. This makes the feedforward
            -- a local hover estimate and lets the PIDs handle target tracking.
            source = "current",
            -- Measured hover curve. Porting to another craft should start by
            -- retuning these few level points, then apply a small global gain
            -- adjustment to the PID values only if needed.
            levels = {
                { altitude = 80, level = 4.00 },
                { altitude = 100, level = 4.60 },
                { altitude = 120, level = 5.25 },
                { altitude = 140, level = 5.75 },
                { altitude = 160, level = 6.00 },
                { altitude = 180, level = 6.50 },
                { altitude = 200, level = 7.05 },
                { altitude = 220, level = 7.60 }
            },
            -- Fallback pressure model. Used only when levels above are removed.
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
        maxStep = 0.2,
        positionMeasurement = {
            field = "altitude",
            scale = 1
        },
        speedMeasurement = {
            field = "down",
            scale = -1
        },
        -- One-pole filter for vertical speed used by the controller.
        -- 1 = no filtering, lower = smoother but slower.
        speedFilterAlpha = 0.35,
        outputs = {
            {
                alias = "TopThruster",
                ratio = 1
            }
        },
        outerPid = {
            kp = 0.05,
            ki = 0.01,
            kd = 0,
            bias = 0,
            -- Outer output is target vertical speed.
            outputMin = -0.35,
            outputMax = 0.35,
            integralMin = -12,
            integralMax = 12,
            integralZone = 8,
            integralLeak = 0.98,
            resetIntegralOnErrorSignChange = true,
            -- Segment output limits trade settling time against overshoot.
            -- Keep gains similar across bands for portability.
            segments = {
                { name = "h080_120", altitudeMin = 80, altitudeMax = 120, outputMin = -0.25, outputMax = 0.25 },
                { name = "h120_170", altitudeMin = 120, altitudeMax = 170, outputMin = -0.30, outputMax = 0.30 },
                { name = "h170_220", altitudeMin = 170, altitudeMax = 220, outputMin = -0.35, outputMax = 0.35 },
                { name = "outside", outputMin = -0.20, outputMax = 0.20 }
            }
        },
        innerPid = {
            kp = 2.6,
            ki = 0.012,
            kd = 0,
            -- Inner PID output is a signed correction added on top of feedforward.
            bias = 0,
            outputMin = -1.2,
            outputMax = 1.2,
            integralMin = -4,
            integralMax = 4,
            integralZone = 0.8,
            integralLeak = 0.98,
            resetIntegralOnErrorSignChange = true,
            segments = {
                { name = "h080_120", altitudeMin = 80, altitudeMax = 120, kp = 1.4, outputMin = -0.9, outputMax = 0.9 },
                { name = "h120_170", altitudeMin = 120, altitudeMax = 170, kp = 1.5, outputMin = -1.0, outputMax = 1.0 },
                { name = "h170_220", altitudeMin = 170, altitudeMax = 220, kp = 1.6, outputMin = -1.2, outputMax = 1.2 },
                { name = "outside", kp = 1.2, outputMin = -0.8, outputMax = 0.8 }
            }
        },
        stopOnSensorError = true
    }
}
