return {
    forwardSpeed = {
        setpoint = 0,
        period = 0.2,
        maxStep = 16,
        outputs = {
            {
                node = "MainThruster",
                alias = "MainThruster",
                ratio = 1
            },
            {
                node = "LeftThruster",
                alias = "LeftThruster",
                ratio = 1
            },
            {
                node = "RightThruster",
                alias = "RightThruster",
                ratio = 1
            }
        },
        pid = {
            kp = 1.5,
            ki = 0,
            kd = 0,
            bias = 0,
            outputMin = -256,
            outputMax = 256,
            integralMin = -256,
            integralMax = 256
        },
        stopOnSensorError = true
    },
    altitudeExperiment = {
        enabled = true,
        period = 0.2,
        positionSetpoint = 0,
        maxStep = 16,
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
                node = "MainThruster",
                alias = "MainThruster",
                ratio = 1
            },
            {
                node = "LeftThruster",
                alias = "LeftThruster",
                ratio = 1
            },
            {
                node = "RightThruster",
                alias = "RightThruster",
                ratio = 1
            }
        },
        outerPid = {
            kp = 1.0,
            ki = 0,
            kd = 0,
            bias = 0,
            outputMin = -20,
            outputMax = 20,
            integralMin = -20,
            integralMax = 20
        },
        innerPid = {
            kp = 1.0,
            ki = 0,
            kd = 0,
            bias = 0,
            outputMin = -256,
            outputMax = 256,
            integralMin = -256,
            integralMax = 256
        },
        stopOnSensorError = true
    },
    display = {
        dashboard = {
            metrics = {
                {
                    key = "speed",
                    label = "Speed",
                    source = "forward"
                },
                {
                    key = "height",
                    label = "Height",
                    source = "altitude",
                    target = 0
                }
            }
        }
    }
}
