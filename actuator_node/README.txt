Put these files on the actuator turtle:

actuator_node.lua
actuator.lua
rpc.lua
config.lua

Edit config.lua if your modem or motor side is different.

Default:
modemSide = right
MainThruster = top

Run:
actuator_node

Config templates:
config_main_thruster.lua
config_left_thruster.lua
config_right_thruster.lua

Rename the matching template to config.lua on each turtle.
