Put these files on the GNSS computer:

gnss_node.lua
gnss.lua
config.lua
rpc.lua

Requirements:
wireless modem
gps host network available

Default:
modemSide = right
role = slave
useLocal = true
slaveIDs = {}
timeout = 2
rpcTimeout = 5
fields = x y z altitude
protocol = aero_control

Run:
gnss_node.lua
