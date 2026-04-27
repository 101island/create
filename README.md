# CC_Airship

CC_Airship 是一组 Lua 脚本，用于通过 `rednet` 在控制端、测速节点和执行器节点之间发送控制消息。

> 运行环境待确认：源码使用了 `rednet`、`peripheral`、`term`、`colors`、`os.getComputerID()` 等 API，通常需要支持这些 API 的 Lua 环境。项目文件没有明确写出具体平台名称。

## 目录结构

```text
.
├── control_hub/       # 控制端脚本
├── airspeed_node/     # 测速节点脚本
├── actuator_node/     # 执行器节点脚本
├── common/            # 公共模块源码和 inspect 工具
├── tools/             # 维护脚本
└── CONFIG_NAMING.txt  # 节点和组件命名约定
```

## 节点与职责

| 目录 | 作用 | 主要文件 |
| --- | --- | --- |
| `control_hub/` | 从控制端向其他节点发送 RPC 消息，读取测速数据或设置执行器转速。 | `config.lua`, `client.lua`, `rpc.lua`, `read_airspeed.lua`, `send_actuator.lua`, `send_node.lua` |
| `airspeed_node/` | 监听测速请求，读取配置中定义的测速外设并返回速度值。 | `airspeed_node.lua`, `airspeed.lua`, `config.lua`, `rpc.lua` |
| `actuator_node/` | 监听执行器控制请求，调用外设的 `setSpeed` 或 `stop` 方法。 | `actuator_node.lua`, `actuator.lua`, `rpc.lua`, `config.lua` |
| `common/` | 公共模块源码。需要部署到节点目录的副本可通过 `tools/sync_common.ps1` 同步。 | `rpc.lua`, `actuator.lua`, `airspeed.lua`, `inspect.lua` |
| `tools/` | 项目维护脚本。 | `sync_common.ps1` |

## 维护约定

- 公共模块优先修改 `common/` 下的源码。
- 修改 `common/rpc.lua`、`common/actuator.lua` 或 `common/airspeed.lua` 后，运行同步脚本把副本复制到节点目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\sync_common.ps1
```

- 节点目录仍保留部署副本，因为每个节点运行时需要本地文件。
- 控制端命令脚本只负责解析命令行参数；RPC 调用集中在 `control_hub/client.lua`。
- 测速节点的外设侧、轴名和别名集中在 `airspeed_node/config.lua`。

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
    MainThruster = "top"
}
```

## 部署

### 控制端

把以下文件放到控制端：

- `control_hub/config.lua`
- `control_hub/client.lua`
- `control_hub/rpc.lua`
- `control_hub/read_airspeed.lua`
- `control_hub/send_actuator.lua`
- `control_hub/send_node.lua`

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
        Rudder1 = 6
    }
}
```

### 测速节点

把以下文件放到测速节点：

- `airspeed_node/airspeed_node.lua`
- `airspeed_node/airspeed.lua`
- `airspeed_node/config.lua`
- `airspeed_node/rpc.lua`

当前源码中的默认配置：

- `modemSide = "right"`
- `bottom`：前向速度
- `left`：垂直速度
- `protocol = "aero_control"`

测速节点配置示例：

```lua
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
```

启动：

```text
airspeed_node
```

### 执行器节点

把以下文件放到执行器节点：

- `actuator_node/actuator_node.lua`
- `actuator_node/actuator.lua`
- `actuator_node/rpc.lua`
- `actuator_node/config.lua`

可按节点类型选择配置模板，并重命名为 `config.lua`：

- `config_main_thruster.lua`
- `config_left_thruster.lua`
- `config_right_thruster.lua`

默认配置示例：

```lua
return {
    protocol = "aero_control",
    modemSide = "right",

    components = {
        MainThruster = "top"
    }
}
```

启动：

```text
actuator_node
```

## 控制端命令

读取测速节点：

```text
read_airspeed
```

按节点 ID 设置执行器转速：

```text
send_actuator <nodeID> <alias> <rpm>
```

示例：

```text
send_actuator 3 MainThruster 100
```

按节点名称设置执行器转速：

```text
send_node <nodeName> <rpm>
send_node <nodeName> <targetAlias> <rpm>
```

示例：

```text
send_node RightThruster 100
send_node RightThruster RightThruster 100
```

## 执行器行为

`actuator.lua` 当前实现的行为：

- `setSpeed(cfg, alias, rpm)` 会把 `rpm` 转成数字。
- `rpm` 无法转成数字时返回 `Invalid RPM`。
- `rpm` 会被限制在 `-256` 到 `256` 之间。
- 外设必须支持 `setSpeed` 方法。
- `stop(cfg, alias)` 会优先调用外设的 `stop` 方法；如果没有 `stop`，但有 `setSpeed`，则调用 `setSpeed(0)`。

## 测速节点行为

`airspeed_node.lua` 当前实现的行为：

- `bottom`、`forward` 或 RPC 目标 `bottom` 会读取前向速度。
- `left`、`back`、`vertical` 或 RPC 目标 `left` 会读取垂直速度。
- 测速外设必须存在并提供 `getVelocity` 方法。
- 如果 `getVelocity()` 返回数字，则直接使用该数字。
- 如果 `getVelocity()` 返回表，前向速度读取 `x` 或第 1 项，垂直速度读取 `y` 或第 2 项；没有对应值时返回 `0`。

## 调试工具

`common/inspect.lua` 可用于查看指定外设侧的类型和方法：

```text
inspect <side>
inspect <side> <method> <arg1> ...
```

例如：

```text
inspect top
inspect top getVelocity
```

## 待确认信息

以下信息未能从当前项目文件中严格确认，暂不写成事实：

- 目标运行平台的准确名称和版本。
- 依赖的外设或模组名称。
- 每个节点 ID 是否只是示例值，还是当前世界/设备中的固定值。
- `Rudder1` 当前是否已有对应执行器脚本或仍是预留名称。
