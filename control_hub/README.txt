Put these files on the control hub:

config.lua
client.lua
display.lua
display/device.lua
display/core.lua
display/menu.lua
display/plot.lua
display/airspeed.lua
display/flight.lua
display/system.lua
control_config.lua
pid.lua
rpc.lua
read_airspeed.lua
read_gnss.lua
monitor_airspeed.lua
display_dashboard.lua
show_flight_display.lua
send_actuator.lua
send_node.lua
run_forward_speed.lua
run_altitude_experiment.lua

Edit config.lua:
modemSide = control hub modem side
nodes.Airspeed = airspeed node ID
nodes.GNSS = GNSS node ID (optional)

Use:
read_airspeed.lua
read_gnss.lua
display.lua dashboard [displaySide] [period] [textScale]
display.lua airspeed <displaySide> [period] [textScale]
display.lua flight <displaySide> [textScale]
display.lua io [displaySide] [period] [textScale]
monitor_airspeed.lua <displaySide> [period] [textScale]
display_dashboard.lua [displaySide] [period] [textScale]
show_flight_display.lua <displaySide> [textScale]
send_actuator.lua <nodeID> <alias> <rpm>
send_node.lua <nodeName> <rpm>
send_node.lua <nodeName> <alias> <rpm>
run_forward_speed.lua [setpoint] [kp] [ki] [kd] [period] [--dry-run]
run_altitude_experiment.lua [positionSetpoint] [outerKp] [innerKp] [period] [--dry-run]

Example:
read_gnss.lua
display.lua dashboard
monitor_airspeed.lua left 0.5 1
display_dashboard.lua top 0.5 0.5
show_flight_display.lua left 1
send_actuator.lua 3 MainThruster 100
send_node.lua RightThruster 100
send_node.lua RightThruster RightThruster 100
run_forward_speed.lua
run_forward_speed.lua 20 1.5 0 0.1 0.2 --dry-run
run_altitude_experiment.lua
run_altitude_experiment.lua 100 1.0 0.8 0.2 --dry-run

Dashboard metrics are configured in control_config.lua:
forwardSpeed.setpoint = optional default target for speed
forwardSpeed.pid.kp = default proportional gain
display.dashboard.metrics = list of displayed items
metric.key = internal key
metric.label = displayed label
metric.source = current value source field
metric.target = target value
If config.lua contains nodes.GNSS, dashboard also reads GNSS altitude.
GNSS role is configured on each GNSS node, not on control_hub.
