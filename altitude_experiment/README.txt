Altitude experiment module

Purpose:
One ComputerCraft computer reads altitude, derives vertical speed, drives one
redstone relay actuator, and runs the altitude/speed cascade PID with monitor
pages for tuning.

Copy these files to the experiment computer:

config.lua
control_config.lua
runtime_state.lua
data_logger.lua
feedforward.lua
pid.lua
altitude.lua
vertical_speed.lua
actuator.lua
io.lua
client.lua
read_io.lua
test_sensors.lua
set_actuator.lua
collect_identification.lua
display.lua
display_dashboard.lua
display/core.lua
display/device.lua
display/menu.lua
display/plot.lua
display/system.lua
run_altitude_experiment.lua

Hardware config:
config.lua

altitude.side:
  Side of the absolute height sensor. Current tested value: right.

display.side:
  Side of the wired modem or monitor peripheral. Current value: top.

display.remoteName:
  Remote monitor name on the wired modem. Current value: monitor_0.

components.TopThruster.peripheralType:
  Actuator peripheral type. Current value: redstone_relay.

components.TopThruster.outputSide:
  Relay output side connected to the thruster command line. Current value: left.

components.TopThruster.scale:
  Output gain before clamping.

components.TopThruster.bias:
  Output offset before clamping.
  Normal 0..15 mapping: scale = 1, bias = 0.
  Inverted 0..15 mapping: scale = -1, bias = 15.

Control config:
control_config.lua

mode:
  cascade = outer altitude loop produces target speed.
  speed = inner speed loop uses speedSetpoint directly.

positionSetpoint:
  Target altitude.

speedSetpoint:
  Manual target speed used by speed mode.

innerPid.outputMin / outputMax:
  Redstone relay analog output range. Current driver range is 0..15.

plotHistory:
  Number of runtime samples kept for the PLT page.

logging:
  CSV logging for MATLAB identification. Disabled by default unless --log is
  passed to run_altitude_experiment.lua.

feedforward:
  Height-dependent hover command. It follows the pressure/hover-fill model from
  the referenced pid.lua:
  final actuator command = feedforward level + signed inner PID correction.
  referenceAltitude and referenceLevel are the measured hover calibration point.

outerPid.segments / innerPid.segments:
  Altitude bands for gain scheduling. A segment may override kp, ki, kd,
  outputMin, outputMax, integralMin, or integralMax. If a field is absent,
  the base PID value is used.

Run tests:
read_io.lua
read_io.lua 0.2
test_sensors.lua
set_actuator.lua TopThruster 0
set_actuator.lua TopThruster 5
set_actuator.lua TopThruster 15

Open-loop MATLAB identification collection:
collect_identification.lua auto 1 5 6 0.2 altitude_id.csv

Arguments:
base|auto = center actuator level. auto uses the feedforward estimate.
amplitude = +/- actuator level around base.
holdSeconds = duration of each step.
cycles = number of alternating high/low steps.
period = sampling period.
logPath = CSV output path.

Run integrated controller and dashboard:
run_altitude_experiment.lua

Optional arguments:
run_altitude_experiment.lua <targetAltitude> <outerKp> <innerKp> <period>
run_altitude_experiment.lua 120 1.0 1.0 0.2
run_altitude_experiment.lua 120 1.0 1.0 0.2 --dry-run
run_altitude_experiment.lua 120 1.0 1.0 0.2 --no-display
run_altitude_experiment.lua 120 1.0 1.0 0.2 --log
run_altitude_experiment.lua 120 1.0 1.0 0.2 --log logs/altitude_step.csv

MATLAB identification:
MATLAB files are kept separately in:
matlab/

Copy the generated CSV log from the ComputerCraft computer into
altitude_experiment/matlab/, then run:
matlab/matlab_identification.m

Logged columns include:
t, target_altitude, altitude, altitude_error, target_speed, speed,
speed_error, output_command, actuator_output, feedforward, correction,
pressure, inner_segment, outer_segment, status.

Standalone display preview:
display.lua dashboard
display.lua dashboard top 0.5 0.5 monitor_0
display.lua io top 0.5 0.5 monitor_0

Dashboard controls:
Monitor touch:
  top menu switches pages: INR, OUT, PLT, IO.
  touch an EDIT row to select it.
  [-] and [+] adjust the selected field.
  [NEXT] selects the next editable field.
  [ON]/[OFF] toggles controller enable.
  [CASCADE]/[SPEED] toggles control mode.

Keyboard:
  Left/right switch pages.
  Up/down select editable field.
  -/+ adjust selected field.
  Space toggles enable.
  m toggles mode.
  r resets both PID integrators.
