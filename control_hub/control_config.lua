return {
    forwardSpeed = {
        setpoint = 0,
        period = 0.2,
        output = {
            node = "MainThruster",
            alias = "MainThruster",
            maxStep = 16
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
    display = {
        dashboard = {
            metrics = {
                {
                    key = "speed",
                    label = "Speed",
                    source = "forward",
                    target = 0
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
