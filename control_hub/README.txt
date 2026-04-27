Put these files on the control hub:

config.lua
client.lua
rpc.lua
read_airspeed.lua
send_actuator.lua
send_node.lua

Edit config.lua:
modemSide = control hub modem side
nodes.Airspeed = airspeed node ID

Use:
read_airspeed
send_actuator <nodeID> <alias> <rpm>
send_node <nodeName> <rpm>
send_node <nodeName> <alias> <rpm>

Example:
send_actuator 3 MainThruster 100
send_node RightThruster 100
send_node RightThruster RightThruster 100
