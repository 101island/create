# CC_Airship

CC_Airship 是一组 Lua 脚本，用于通过 `rednet` 在控制端、测速节点和执行器节点之间发送控制消息。

> 运行环境待确认：源码使用了 `rednet`、`peripheral`、`term`、`colors`、`os.getComputerID()` 等 API，通常需要支持这些 API 的 Lua 环境。项目文件没有明确写出具体平台名称。

## 目录结构

```text
.
├── control_hub/       # 控制端脚本
├── altitude_experiment/ # 高度串级实验电脑脚本
├── airspeed_node/     # 测速节点脚本
├── gnss/              # GNSS 节点脚本
├── actuator_node/     # 执行器节点脚本
├── common/            # 公共模块源码和 inspect 工具
└── CONFIG_NAMING.txt  # 节点和组件命名约定
```

## 节点与职责

| 目录 | 作用 | 主要文件 |
| --- | --- | --- |
| `control_hub/` | 从控制端向其他节点发送 RPC 消息，读取测速数据、GNSS 数据、显示测速数显、设置执行器转速，运行前行速度控制环和高度串级实验环。 | `config.lua`, `client.lua`, `display/`, `control_config.lua`, `pid.lua`, `rpc.lua`, `read_airspeed.lua`, `read_gnss.lua`, `monitor_airspeed.lua`, `display_dashboard.lua`, `show_flight_display.lua`, `send_actuator.lua`, `send_node.lua`, `run_forward_speed.lua`, `run_altitude_experiment.lua` |
| `altitude_experiment/` | 高度串级实验电脑的独立部署目录。本机直接读取速度/高度并直接驱动本机推进器，不经过 `rednet`。 | `config.lua`, `client.lua`, `io.lua`, `airspeed.lua`, `gnss.lua`, `actuator.lua`, `control_config.lua`, `pid.lua`, `read_io.lua`, `set_actuator.lua`, `run_altitude_experiment.lua`, `README.txt` |
| `airspeed_node/` | 监听测速请求，读取配置中定义的测速外设并返回速度值。 | `airspeed_node.lua`, `airspeed.lua`, `config.lua`, `rpc.lua` |
| `gnss/` | 监听 GNSS 请求，读取 GPS 定位并返回 `x/y/z/altitude`。 | `gnss_node.lua`, `gnss.lua`, `config.lua`, `rpc.lua` |
| `actuator_node/` | 监听执行器控制请求，调用外设的 `setSpeed`、`setGeneratedSpeed` 或 `stop` 方法。 | `actuator_node.lua`, `actuator.lua`, `rpc.lua`, `config.lua` |
| `common/` | 公共模块源码和外设 inspect 工具。节点目录内的运行文件独立维护，不再通过同步脚本复制。 | `rpc.lua`, `actuator.lua`, `airspeed.lua`, `gnss.lua`, `pid.lua`, `inspect.lua` |

## 维护约定

- 公共模块优先修改 `common/` 下的源码。
- 节点目录保留运行文件；需要修改节点行为时，直接维护对应节点目录内的文件。
- 显示模块只维护 `control_hub/display/` 下的源码，不再维护根目录 `display/`，也不通过同步脚本复制显示模块副本。
- 控制端命令脚本只负责解析命令行参数；RPC 调用集中在 `control_hub/client.lua`。
- 测速节点是测速通道的单一配置来源：请求名采用前-右-下坐标系，外设侧、轴名和显示顺序集中在 `airspeed_node/config.lua`。
- GNSS 节点是绝对坐标和绝对高度的单一配置来源：字段顺序和 `gps.locate()` 超时集中在 `gnss/config.lua`。
- `control_hub/display/` 是显示终端模块：它负责获取显示所需数据、管理刷新周期、处理显示屏菜单、调用页面绘制组件。
- `control_hub/display/` 不负责控制闭环和执行器输出；PID、目标值计算和执行器写入仍由控制模块负责。
- 前行速度环的周期、输出对象、限幅和安全行为集中在 `control_hub/control_config.lua`。

## 通信协议

- 默认协议名：`aero_control`
- 控制端配置文件：`control_hub/config.lua`
- 执行器节点配置文件：`actuator_node/config.lua`
- 默认 `modemSide`：`right`

控制端通过 `rpc.call(nodeID, protocol, target, method, args, timeout)` 发送表结构消息：

```lua
{
    target = target,
    method = method,
    args = args or {}
}
```

节点通过以下结构回复：

```lua
{
    ok = ok,
    value = value
}
```

## 命名约定

`CONFIG_NAMING.txt` 中列出的名称应在配置中保持一致：

- `MainThruster`
- `LeftThruster`
- `RightThruster`
- `Airspeed`
- `Rudder1`

控制端使用 `nodes` 表把节点名映射到节点 ID：

```lua
nodes = {
    MainThruster = 3,
    LeftThruster = 4,
    RightThruster = 5,
    Airspeed = 2,
    Rudder1 = 6
}
```

执行器节点使用 `components` 表把组件别名映射到外设位置：

```lua
components = {
    MainThruster = {
        side = "left",
        scale = 1
    }
}
```

## 部署

### 控制端

把以下文件放到控制端：

- `control_hub/config.lua`
- `control_hub/client.lua`
- `control_hub/display.lua`
- `control_hub/display/device.lua`
- `control_hub/display/core.lua`
- `control_hub/display/menu.lua`
- `control_hub/display/plot.lua`
- `control_hub/display/airspeed.lua`
- `control_hub/display/flight.lua`
- `control_hub/display/system.lua`
- `control_hub/control_config.lua`
- `control_hub/pid.lua`
- `control_hub/rpc.lua`
- `control_hub/read_airspeed.lua`
- `control_hub/read_gnss.lua`
- `control_hub/monitor_airspeed.lua`
- `control_hub/display_dashboard.lua`
- `control_hub/show_flight_display.lua`
- `control_hub/send_actuator.lua`
- `control_hub/send_node.lua`
- `control_hub/run_forward_speed.lua`
- `control_hub/run_altitude_experiment.lua`

根据实际节点 ID 修改 `control_hub/config.lua`：

```lua
return {
    protocol = "aero_control",
    modemSide = "right",

    nodes = {
        MainThruster = 3,
        LeftThruster = 4,
        RightThruster = 5,
        Airspeed = 2,
        GNSS = 7,
        Rudder1 = 6
    }
}
```

如果当前没有 GNSS 节点，可以先不配置 `GNSS`。

### 高度串级实验电脑

把以下文件放到实验电脑：

- `altitude_experiment/config.lua`
- `altitude_experiment/client.lua`
- `altitude_experiment/airspeed.lua`
- `altitude_experiment/gnss.lua`
- `altitude_experiment/actuator.lua`
- `altitude_experiment/control_config.lua`
- `altitude_experiment/pid.lua`
- `altitude_experiment/read_io.lua`
- `altitude_experiment/set_actuator.lua`
- `altitude_experiment/run_altitude_experiment.lua`

这个目录是本机直连版：

- 速度传感器由 `config.lua -> sensors` 定义
- 高度由本机 `gps.locate()` 读取
- 执行器由 `config.lua -> components` 定义
- 不依赖 `rednet`、节点 ID 或远端执行器节点

当前配置模板示例：

```lua
return {
    sensors = {
        forward = {
            side = "left",
            axis = "x",
            index = 1,
            scale = -1
        },
        down = {
            side = "right",
            axis = "y",
            index = 2,
            scale = 1
        }
    },
    sensorOrder = { "forward", "down" },
    gnss = {
        timeout = 2,
        fieldOrder = { "x", "y", "z", "altitude" }
    },
    components = {
        TopThruster = {
            side = "top",
            scale = 1
        }
    }
}
```

调驱动可先执行：

```text
read_io.lua
set_actuator.lua TopThruster 64
```

运行串级实验：

```text
run_altitude_experiment.lua
run_altitude_experiment.lua 100 1.0 0.8 0.2 --dry-run
```

### 测速节点

把以下文件放到测速节点：

- `airspeed_node/airspeed_node.lua`
- `airspeed_node/airspeed.lua`
- `airspeed_node/config.lua`
- `airspeed_node/rpc.lua`

当前源码中的默认配置：

- `modemSide = "right"`
- `forward` 请求：读取 `top` 侧外设
- `down` 请求：读取 `left` 侧外设
- `protocol = "aero_control"`

测速节点配置示例：

```lua
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
```

启动：

```text
airspeed_node.lua
```

### GNSS 节点

把以下文件放到 GNSS 节点：

- `gnss/gnss_node.lua`
- `gnss/gnss.lua`
- `gnss/config.lua`
- `gnss/rpc.lua`

当前源码中的默认配置：

- `modemSide = "right"`
- `role = "slave"`
- `useLocal = true`
- `slaveIDs = {}`
- `timeout = 2`
- `rpcTimeout = 5`
- `fieldOrder = { "x", "y", "z", "altitude" }`
- `protocol = "aero_control"`

GNSS 节点配置示例：

```lua
return {
    protocol = "aero_control",
    modemSide = "right",
    role = "slave",
    useLocal = true,
    slaveIDs = {},
    timeout = 2,
    rpcTimeout = 5,
    fieldOrder = { "x", "y", "z", "altitude" }
}
```

主从约定：

- `role = "slave"`：只输出本机 `gps.locate()` 的结果
- `role = "master"`：轮询 `slaveIDs` 中的从机，并与可选的本机定位一起解算最终值
- `useLocal = true`：表示该节点自己的 `gps.locate()` 也参与输出

因此中控只需要把 `nodes.GNSS` 指向主 GNSS 节点。

启动：

```text
gnss_node.lua
```

### 执行器节点

把以下文件放到执行器节点：

- `actuator_node/actuator_node.lua`
- `actuator_node/actuator.lua`
- `actuator_node/rpc.lua`
- `actuator_node/config.lua`

执行器节点只保留一个配置文件：`actuator_node/config.lua`。

当前配置模板示例：

```lua
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
        --
        -- scale controls motor polarity:
        -- 1 keeps the command direction
        -- -1 reverses the command direction
        MainThruster = {
            side = "left",
            scale = 1
        }
    }
}
```

启动：

```text
actuator_node.lua
```

## 控制端命令

如果传输到运行环境后的文件名保留 `.lua` 后缀，执行命令时也要带 `.lua`。例如截图中的文件是 `show_flight_display.lua`，应执行：

```text
show_flight_display.lua top
```

如果手动把命令文件重命名为无后缀文件，才可以省略 `.lua`。

读取测速节点：

```text
read_airspeed.lua
read_gnss.lua
```

把测速数据持续显示到显示屏外设：

```text
monitor_airspeed.lua <displaySide> [period] [textScale]
```

示例：

```text
monitor_airspeed.lua left 0.5 1
```

说明：

- `displaySide`：显示屏外设所在侧。
- `period`：刷新周期，默认 `0.5` 秒。
- `textScale`：文字缩放，默认 `1`。
- 显示哪些测速通道由测速节点返回的 `sensorOrder` 决定；中控不重复配置通道列表。
- `forward` 通道的目标值显示默认来自 `control_hub/control_config.lua` 中的 `forwardSpeed.setpoint`。

3x3 显示屏仪表盘：

```text
display_dashboard.lua [displaySide] [period] [textScale]
```

也可以使用菜单式入口：

```text
display.lua dashboard [displaySide] [period] [textScale]
display.lua airspeed <displaySide> [period] [textScale]
display.lua flight <displaySide> [textScale]
display.lua io [displaySide] [period] [textScale]
```

示例：

```text
display_dashboard.lua top 0.5 0.5
display.lua dashboard
```

说明：

- 默认 `displaySide = top`，适合显示屏放在中控终端上方的安装方式。
- 默认 `period = 0.5` 秒。
- 默认 `textScale = 0.5`，适合较大的 3x3 显示屏显示更多内容。
- 顶部菜单包含 `AIR`、`PLOT`、`FC`。
- 顶部菜单包含 `AIR`、`PLOT`、`FC`、`IO`。
- 支持显示屏点击顶部菜单切换页面；如果运行环境提供 `keys`，也可用左右方向键切换。
- `AIR` 页显示目标速度、当前速度、目标高度、当前高度。
- `PLOT` 页绘制速度和高度的时序图，其中目标值是常值线，当前值来自测速节点返回的数据源。
- `IO` 页显示当前传感器和执行器的数值汇总。

显示飞控姿态数显框架：

```text
show_flight_display.lua <displaySide> [textScale]
```

示例：

```text
show_flight_display.lua left 1
```

`control_hub/display/flight.lua` 按飞控常用命名显示两组数据：

- 姿态：`roll`、`pitch`、`yaw`
- 姿态变化率：`p`、`q`、`r`
- 每项均显示当前值 `CUR` 和目标值 `TGT`

数据结构约定：

```lua
{
    attitude = {
        roll = { current = 0, target = 0 },
        pitch = { current = 0, target = 0 },
        yaw = { current = 0, target = 0 }
    },
    rates = {
        p = { current = 0, target = 0 },
        q = { current = 0, target = 0 },
        r = { current = 0, target = 0 }
    }
}
```

当前项目还没有姿态传感器或姿态目标来源；后续确定姿态数据来源后，应由显示入口脚本获取真实状态，再调用 `control_hub/display/flight.lua` 绘制。

按节点 ID 设置执行器转速：

```text
send_actuator.lua <nodeID> <alias> <rpm>
```

示例：

```text
send_actuator.lua 3 MainThruster 100
```

按节点名称设置执行器转速：

```text
send_node.lua <nodeName> <rpm>
send_node.lua <nodeName> <targetAlias> <rpm>
```

示例：

```text
send_node.lua RightThruster 100
send_node.lua RightThruster RightThruster 100
```

运行前行速度 PID 环：

```text
run_forward_speed.lua [setpoint] [kp] [ki] [kd] [period] [--dry-run]
```

示例：

```text
run_forward_speed.lua
run_forward_speed.lua 20 1.5 0 0.1 0.2 --dry-run
```

参数含义：

- `setpoint`：目标前行速度。
- `kp`、`ki`、`kd`：PID 参数。
- `period`：控制周期，默认来自 `control_hub/control_config.lua`。
- `--dry-run`：只打印控制结果，不向执行器发送转速。

如果命令行不传数值参数，`run_forward_speed.lua` 会直接使用 `control_hub/control_config.lua` 中的 `forwardSpeed.setpoint`、`forwardSpeed.pid.kp`、`ki`、`kd` 和 `period`。

当前前行速度环读取 `Airspeed` 节点的前向速度，并把一个基础 PID 输出量按固定比例分配到 `control_config.lua` 中配置的多个执行器。传感器读取失败时，默认向全部输出通道发送 `0` 转速。

前行速度环配置示例：

```lua
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
```

其中：

- `maxStep` 限制每个控制周期内“基础输出量”的最大变化量。
- `outputs` 定义参与前行速度环的执行器列表。
- 每个输出项的 `ratio` 表示该执行器相对于基础输出量的固定比例。

运行高度串级实验环：

```text
run_altitude_experiment.lua [positionSetpoint] [outerKp] [innerKp] [period] [--dry-run]
```

示例：

```text
run_altitude_experiment.lua
run_altitude_experiment.lua 100 1.0 0.8 0.2 --dry-run
```

当前实验模块的职责：

- 读取 GNSS 高度字段作为外层位置测量。
- 读取测速节点速度字段作为内层速度测量。
- 外层位置环输出速度目标。
- 内层速度环输出推进器基础输出量。
- 基础输出量再按固定比例分配到多个推进器。

默认配置位于 `control_hub/control_config.lua` 的 `altitudeExperiment` 段，例如：

```lua
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
        { node = "MainThruster", alias = "MainThruster", ratio = 1 },
        { node = "LeftThruster", alias = "LeftThruster", ratio = 1 },
        { node = "RightThruster", alias = "RightThruster", ratio = 1 }
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
}
```

其中：

- `positionMeasurement.field` 定义外层位置环读取哪个字段。
- `speedMeasurement.field` 定义内层速度环读取哪个字段。
- `scale` 用于把传感器原始符号转换到控制所需符号。
- `outerPid` 是位置环参数。
- `innerPid` 是速度环参数。

`display.dashboard.metrics` 定义 dashboard 要显示和绘制的量。每个条目都包含：

- `key`：内部键名，用于历史曲线和状态索引
- `label`：显示名
- `source`：当前值数据源名称
- `target`：目标值

例如：

- `source = "forward"` 表示当前速度来自测速节点返回的 `forward`
- `source = "altitude"` 表示当前高度来自 GNSS 或其他节点返回的 `altitude`

当前默认测速节点只返回 `forward` 和 `down`，没有 `altitude`，所以当前高度会显示为 `--`。接入真实高度源后，只需把对应条目的 `source` 改成真实字段名即可。

如果配置了 `nodes.GNSS`，dashboard 会额外读取 GNSS 节点，并把 `altitude` 合并到显示数据中。此时某个 metric 的 `source = "altitude"` 会直接读取 GNSS 返回的绝对高度。

按当前实现，后续新增显示项时，通常只需要：

- 在对应节点中回传新的字段
- 在 `display.dashboard.metrics` 中新增一个条目

不需要再改 `display` 代码。

## 执行器行为

`actuator.lua` 当前实现的行为：

- `setSpeed(cfg, alias, rpm)` 会把 `rpm` 转成数字。
- `rpm` 无法转成数字时返回 `Invalid RPM`。
- `rpm` 会被限制在 `-256` 到 `256` 之间。
- `components.<alias>.scale` 可用于执行器极性调节；`1` 表示保持方向，`-1` 表示反向。
- 外设必须支持 `setSpeed` 或 `setGeneratedSpeed` 方法之一。
- `stop(cfg, alias)` 会优先调用外设的 `stop` 方法；如果没有 `stop`，但有 `setSpeed` 或 `setGeneratedSpeed`，则调用对应方法并写入 `0`。

## 测速节点行为

`airspeed_node.lua` 当前实现的行为：

- 请求名只接受 `airspeed_node/config.lua` 中 `sensors` 表的键名。
- 当前默认请求名是 `forward` 和 `down`。
- 中控读取测速时只发送一次 `readAll` 请求；返回哪些通道由测速节点的 `sensors` 和 `sensorOrder` 决定。
- 坐标命名采用前-右-下：`forward` 表示前向，`right` 表示右向，`down` 表示下向。
- 当前默认配置未定义 `right` 通道；如需右向速度，需要在 `sensors` 表中增加 `right`。
- 每个通道可通过 `scale` 配置极性和倍率；`-1` 表示反号，`1` 表示保持原值。
- 测速外设必须存在并提供 `getVelocity` 方法。
- 如果 `getVelocity()` 返回数字，则直接使用该数字。
- 如果 `getVelocity()` 返回表，`forward` 读取 `x` 或第 1 项，`down` 读取 `y` 或第 2 项；没有对应值时返回 `0`。

## GNSS 节点行为

`gnss_node.lua` 当前实现的行为：

- 请求名只接受 `gnss/config.lua` 中 `fieldOrder` 定义的键名。
- 当前默认字段名是 `x`、`y`、`z`、`altitude`。
- 中控读取 GNSS 时只发送一次 `readAll` 请求；返回哪些字段由 GNSS 节点的 `fieldOrder` 决定。
- `slave` 节点通过 `gps.locate(timeout)` 读取本机坐标。
- `master` 节点会读取 `slaveIDs` 中从机的本机定位结果，并做平均解算。
- `altitude` 当前等于 `y`，用于给显示层和后续高度控制提供统一字段名。
- `gps.locate()` 不可用或定位失败时，请求返回错误。

## 调试工具

`common/inspect.lua` 可用于查看指定外设侧的类型和方法：

```text
inspect.lua <side>
inspect.lua <side> <method> <arg1> ...
```

例如：

```text
inspect.lua top
inspect.lua top getVelocity
```

## 待确认信息

以下信息未能从当前项目文件中严格确认，暂不写成事实：

- 目标运行平台的准确名称和版本。
- 依赖的外设或模组名称。
- 每个节点 ID 是否只是示例值，还是当前世界/设备中的固定值。
- `Rudder1` 当前是否已有对应执行器脚本或仍是预留名称。
