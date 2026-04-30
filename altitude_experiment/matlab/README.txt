MATLAB / Simulink bridge folder

Purpose:
This folder keeps the MATLAB/Simulink passthrough layer and host-side
experiment helpers. Generated logs, autosaves, and local model data are ignored.

Current bridge path:
Simulink or MATLAB -> cc_bridge_*.m -> bridge_host.py HTTP API
-> matlab_bridge.lua WebSocket -> ComputerCraft io.lua / actuator.lua

PC bridge:
From the repository root:
python altitude_experiment/matlab/bridge_host.py --host 0.0.0.0 --port 8768 --token <token>

ComputerCraft bridge:
Through the public FRP tunnel:
matlab_bridge.lua ws://<FRP_HOST>:<FRP_PORT>/cc 0.2 TopThruster <token>

Local LAN alternative:
matlab_bridge.lua ws://<PC_IP>:8768/cc 0.2 TopThruster <token>

MATLAB setup:
addpath("D:\Work\Project\CC_Airship\altitude_experiment\matlab")
baseUrl = "http://127.0.0.1:8768";
token = getenv("CC_AIRSHIP_BRIDGE_TOKEN");
alias = "TopThruster";

Passthrough functions:
cc_bridge_config(baseUrl, token, alias)
  Returns a small config struct. Empty arguments use defaults.

cc_bridge_read(baseUrl, token, alias)
  Reads current state and returns a fixed numeric column vector:
  [altitude; vertical_speed; actuator_output; connected; cc_t; ok]

cc_bridge_write(command, baseUrl, token, alias)
  Sends one actuator command through the bridge. command is the redstone level
  expected by the current actuator driver, normally 0..15.

cc_bridge_stop(baseUrl, token, alias)
  Sends command = 0.

sable_set_height_trigger(height, trigger)
  Resets the Sable/Create Simulated vehicle height through ssh + rcon-cli on a
  trigger rising edge. This is not a ComputerCraft peripheral write.
  height is the target altitude-sensor reading, not raw Sable pose Y.
  Output is [ok; fired; status].

sable_set_height_once(height)
  Resets height immediately once. Use this from a Dashboard Callback Button.
  height is the target altitude-sensor reading, not raw Sable pose Y.
  Output is [ok; status].

Minimal MATLAB smoke test:
y = cc_bridge_read(baseUrl, token, alias)
ok = cc_bridge_write(7.5, baseUrl, token, alias)
pause(1)
cc_bridge_stop(baseUrl, token, alias)

Height reset smoke test:
sable_set_height_once(150)
sable_set_height_trigger(150, 0)
sable_set_height_trigger(150, 1)
sable_set_height_trigger(150, 1)
sable_set_height_trigger(150, 0)

Simulink usage:
Use an Interpreted MATLAB Function block first. This is the simplest path for
early experiments because webread/webwrite are MATLAB runtime calls, not code
generation targets.

Read block expression:
cc_bridge_read(baseUrl, token, alias)

Write block expression:
cc_bridge_write(u, baseUrl, token, alias)

Height reset block expression:
sable_set_height_trigger(height_cmd, reset_trigger)

For a MATLAB Function block, mark the passthrough function extrinsic and
pre-allocate fixed-size outputs, for example:

function y = read_airship()
coder.extrinsic('cc_bridge_read');
y = nan(6,1);
y = cc_bridge_read();
end

Current limitation:
The passthrough layer does not do logging, plotting, or identification. Height
reset uses the external Sable/RCON command path, not CraftOS peripherals.
