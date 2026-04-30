# altitude_experiment 代码库导读

## 这是什么

`altitude_experiment/` 是一套运行在 ComputerCraft 环境里的高度控制实验代码。

它把一个绝对高度传感器和一个红石执行器串起来，形成一个两层控制器：

- 外环：高度 PID，把“目标高度”转换成“目标速度”
- 内环：速度 PID，把“目标速度”转换成“执行器修正量”
- 前馈：根据高度估算维持悬停所需的基础输出
- 最终输出：`前馈输出 + 内环修正`，再映射到红石模拟输出 `0..15`

这套代码同时提供：

- 传感器/执行器单独测试脚本
- 集成控制主程序
- 监视器仪表盘，用于在线观察和调参

## 目录结构

### 入口与运维脚本

- `run_altitude_experiment.lua`：主入口，启动控制循环和显示面板
- `display.lua`：单独启动显示界面，适合预览 dashboard / IO 页面
- `read_io.lua`：周期性打印当前传感器与执行器状态
- `test_sensors.lua`：简单传感器/执行器观察脚本
- `set_actuator.lua`：手动设置执行器输出

### 控制核心

- `runtime_state.lua`：运行时核心状态机，负责每一步采样、计算、限幅、输出、历史记录
- `pid.lua`：通用 PID 实现
- `feedforward.lua`：高度到悬停基础输出的前馈模型

### 硬件抽象

- `altitude.lua`：读取绝对高度传感器
- `vertical_speed.lua`：由高度差分估算垂直速度
- `actuator.lua`：执行器封装，支持缩放、偏置、限幅、PWM 抖动量化
- `io.lua`：组合读取全部传感器和执行器
- `client.lua`：对外提供简化调用接口

### 配置

- `config.lua`：硬件连接与执行器映射
- `control_config.lua`：控制参数、设定值、前馈、增益调度

### 显示层

- `display_dashboard.lua`：主仪表盘控制逻辑和交互
- `display/core.lua`：显示基础操作
- `display/device.lua`：本地/远程 monitor 适配
- `display/menu.lua`：顶部菜单栏
- `display/plot.lua`：曲线图页面
- `display/system.lua`：IO 状态页面

### 说明文档

- `README.txt`：部署、运行和操作说明

## 控制链路

主流程在 `run_altitude_experiment.lua` 和 `runtime_state.lua`。

每个控制周期大致这样执行：

1. 读取传感器
2. 从传感器数据中提取高度和速度测量值
3. 根据当前高度选择外环/内环 PID 的增益段
4. 如果是 `cascade` 模式，用外环 PID 把目标高度转成目标速度
5. 计算前馈输出（基础悬停推力）
6. 用内环 PID 算出速度修正量
7. 将 `前馈 + 修正量` 合成为基础输出
8. 做执行器限幅与单步变化限制
9. 写入一个或多个执行器
10. 刷新 IO 快照和历史曲线数据

可以把它理解成下面这条数据流：

```text
高度传感器 -> 高度
高度差分 -> 垂直速度

目标高度 --外环 PID--> 目标速度
目标速度 + 当前速度 --内环 PID--> 修正量
目标高度/当前高度 --前馈模型--> 基础输出

基础输出 + 修正量 -> 执行器命令 -> 红石模拟输出
```

## 两种控制模式

`control_config.lua` 里定义了两种模式：

- `cascade`
  - 正常模式
  - 外环根据高度误差生成目标速度
  - 内环再根据速度误差驱动执行器

- `speed`
  - 调试模式
  - 跳过外环，直接使用 `speedSetpoint`
  - 适合单独调内环 PID

切换模式时，`runtime_state.toggleMode()` 会重置 PID 积分状态，避免旧状态污染新模式。

## 运行时状态 `runtime_state.lua`

`runtime_state.lua` 是整个项目最重要的文件。

### 它负责什么

- 加载硬件配置和控制配置
- 构造运行时对象 `runtime`
- 管理启停、模式切换、设定值调整、PID 参数调整
- 每步执行完整控制逻辑
- 保存最近的 IO、控制输出、前馈状态、历史曲线数据
- 生成简洁状态摘要，供终端打印

### `runtime` 里主要有哪些数据

- `enabled`：控制器是否启用
- `mode`：`cascade` 或 `speed`
- `setpoints.altitude`：目标高度
- `setpoints.speed`：目标速度
- `outerPid` / `innerPid`：两层 PID 的当前状态
- `feedforward`：前馈模型
- `io.sensors` / `io.actuators`：最近一次 IO 快照
- `position`：高度相关的当前值、误差、外环输出
- `speed`：速度相关的当前值、误差、内环信息
- `output`：最终执行器输出、前馈值、修正值
- `history.samples`：给 PLT 页面使用的历史样本
- `status`：当前状态文字，例如 `ok`、`disabled`、某个错误信息

### `step()` 做了什么

`runtime_state.step(runtime, options)` 是每个周期的主函数。

关键逻辑：

- 自动计算 `dt`
- 调用 `io.readSensors()` 采样
- 用 `positionMeasurement` / `speedMeasurement` 指定哪个字段是控制量
- 依据当前高度应用 PID 分段参数
- 处理传感器错误，必要时自动停机并把输出拉到 0
- 在 `cascade` 模式下执行外环 PID
- 执行前馈模型和内环 PID
- 应用 `maxStep`，限制每个周期输出变化幅度
- 真机模式下调用 `actuator.setOutput()`，`dryRun` 模式下只预览命令
- 把结果压入 `history.samples`

## 传感器与执行器抽象

### 高度读取 `altitude.lua`

- 使用 `peripheral.wrap(side)` 获取设备
- 要求设备提供 `getHeight()` 方法
- 支持 `scale` 和 `bias` 做线性校正

### 垂直速度 `vertical_speed.lua`

- 不是直接读速度传感器，而是用连续两次高度读数做差分
- 速度 = `(当前高度 - 上次高度) / dt`
- 每个传感器可配置 `scale`
- 当前配置里只有一个速度字段：`down`

注意：这个模块用文件级 `lastHeight` / `lastTime` 保存上一次采样，因此它本质上是“有状态”的单实例速度估算器。

### 执行器 `actuator.lua`

执行器默认面向 `redstone_relay` 外设。

支持这些能力：

- `scale` / `bias`：把控制命令映射到硬件输出
- `outputMin` / `outputMax`：输出限幅
- 误差累积量化：当输出不是整数时，用跨 tick 的抖动逼近小数平均值

例如输出 7.4 时，模块会在多个周期里按误差累积结果交替输出 7 和 8，让长期平均值接近 7.4。

## 前馈模型 `feedforward.lua`

这个模块的目标不是“纠错”，而是“先给一个大致能悬停的基础输出”。

思路是：

- 高度越高，空气密度越低
- 为维持悬停，需要更高的基础输出
- 先根据高度估算压力（密度）
- 再用标定模型 `n_hover = A + C / rho(h + delta_h)` 直接得到悬停输出

模型来源于 `control_config.lua` 中的参数：

- `calibrationOffsetA` / `calibrationConstantC` / `deltaH`：悬停标定参数
- `capacity` / `maxSteamOutput`：系统容量与输出上限
- `pressure`：压力曲线参数，默认会自动生成一条分段平滑曲线

`feedforward.source` 决定用什么高度去查前馈：

- `target`：用目标高度
- `current`：用当前高度
- `speedTarget`：代码里也支持，但这里返回的是 `runtime.position.output`，也就是外环产生的速度目标；名字上更像实验接口，不是最直观的生产配置

## PID 与增益调度

`pid.lua` 本身很简单：

- 误差 = `setpoint - measurement`
- 积分项带上下限
- 微分项基于误差变化率
- 输出带上下限

真正和工程场景相关的部分在 `runtime_state.lua`：

- 每一步都会根据当前高度挑选一个 segment
- 先应用基础 PID 参数
- 再用当前 segment 覆盖指定字段

也就是说，`control_config.lua` 里的：

- `outerPid.segments`
- `innerPid.segments`

可以按高度区间配置不同的 `kp/ki/kd`、输出范围、积分范围。

当前默认只定义了三个高度段：

- `low`：`< 128`
- `mid`：`128 ~ 256`
- `high`：`>= 256`

但每个段里还没有写具体覆盖参数，说明这是为后续实测调参预留的结构。

## 配置文件怎么读

### `config.lua`

它描述“机器怎么接”。

重点字段：

- `altitude.side`：高度传感器在哪一侧
- `display.side`：monitor 或 wired modem 在哪一侧
- `display.remoteName`：远程 monitor 名称
- `components.TopThruster`：执行器配置

当前硬件默认值体现了一个很明确的假设：

- 只有一个执行器 `TopThruster`
- 输出通过 `redstone_relay` 的 `left` 侧模拟红石发出

### `control_config.lua`

它描述“控制器怎么工作”。

重点字段：

- `enabled`：默认是否启动控制
- `mode`：`cascade` 或 `speed`
- `period`：控制周期
- `displayPeriod`：显示刷新周期
- `positionSetpoint` / `speedSetpoint`：默认目标值
- `positionMeasurement.field`：高度控制使用哪个传感器字段
- `speedMeasurement.field`：速度控制使用哪个字段
- `outputs`：最终输出发给哪些执行器，以及比例
- `maxStep`：每周期最大输出变化量
- `stopOnSensorError`：传感器出错时是否停机

当前默认测量映射是：

- 高度来自 `sensors.altitude`
- 速度来自 `sensors.down * -1`

这说明控制方向经过了符号约定处理，避免传感器正负方向和执行器推力方向不一致。

## 显示系统

### 主界面 `display_dashboard.lua`

这是一个带交互的监视器 UI。

页面有 4 个：

- `INR`：内环速度页
- `OUT`：外环高度页
- `PLT`：历史曲线页
- `IO`：传感器/执行器页

支持两种交互：

- monitor touch / mouse click
- 键盘快捷键

可以在线完成：

- 启停控制器
- 切换 `cascade` / `speed`
- 修改目标高度或目标速度
- 修改内外环 PID 参数
- 重置 PID 积分状态

### `INR` 页看什么

- 目标速度
- 当前速度
- 速度误差
- 内环 PID 修正量
- 前馈输出
- 最终输出
- 当前内环所处 segment

### `OUT` 页看什么

- 目标高度
- 当前高度
- 高度误差
- 外环输出的目标速度
- 当前外环 segment

### `PLT` 页怎么画

`display/plot.lua` 使用 ASCII 风格字符图：

- `*` 表示当前值
- `-` 表示目标值

显示两张图：

- 速度当前值 vs 速度目标值
- 高度当前值 vs 高度目标值

数据来自 `runtime.history.samples`。

### `IO` 页看什么

`display/system.lua` 会列出：

- 传感器值和错误
- 执行器输出和错误

这页很适合排查“控制没动起来”到底是传感器问题还是执行器问题。

## 命令行入口怎么用

### 启动主控制器

```lua
run_altitude_experiment.lua
run_altitude_experiment.lua 120 1.0 1.0 0.2
run_altitude_experiment.lua 120 1.0 1.0 0.2 --dry-run
run_altitude_experiment.lua 120 1.0 1.0 0.2 --no-display
```

参数含义：

- 第 1 个：目标高度
- 第 2 个：外环 `kp`
- 第 3 个：内环 `kp`
- 第 4 个：控制周期
- `--dry-run`：只算不打输出
- `--no-display`：不启动显示线程

### 单独看显示

```lua
display.lua dashboard
display.lua dashboard top 0.5 0.5 monitor_0
display.lua io top 0.5 0.5 monitor_0
```

这里 `display.lua` 会创建一个默认 `runtime`，并由 dashboard 自己做采样，不会真的驱动执行器。

### 看 IO

```lua
read_io.lua
read_io.lua 0.2
test_sensors.lua
```

### 手动打执行器

```lua
set_actuator.lua TopThruster 0
set_actuator.lua TopThruster 5
set_actuator.lua TopThruster 15
```

## 典型阅读顺序

如果要快速理解代码，建议按这个顺序读：

1. `README.txt`
2. `run_altitude_experiment.lua`
3. `runtime_state.lua`
4. `control_config.lua`
5. `pid.lua`
6. `feedforward.lua`
7. `io.lua` / `altitude.lua` / `vertical_speed.lua` / `actuator.lua`
8. `display_dashboard.lua`

这样可以先建立整体心智模型，再看细节实现。

## 这个代码库的设计特点

### 优点

- 分层清楚：采样、控制、执行、显示分开
- `runtime_state.lua` 把运行时状态集中管理，便于调试和显示
- 支持 `dryRun`，适合先验算控制逻辑
- 支持在线调参，便于实验环境快速迭代
- 预留了高度分段增益调度结构，适合后续实测扩展

### 需要注意的点

- `vertical_speed.lua` 的速度估算依赖模块级历史状态，不适合多实例并行使用
- `actuator.wrap()` 用 `peripheral.find(peripheralType)` 找设备，没有按别名绑定具体外设；如果同类外设不止一个，需要额外小心
- `feedforward.source == "speedTarget"` 的语义和实现并不完全直观，更像实验分支
- 显示与控制共用同一个 `runtime` 对象，优点是简单，代价是状态耦合较紧

## 一句话总结

`altitude_experiment/` 是一个面向 ComputerCraft 飞行/升力实验场景的高度控制小系统：用高度与速度构成串级 PID，用前馈补偿不同高度的悬停需求，并通过 monitor UI 支持在线观察和调参。
