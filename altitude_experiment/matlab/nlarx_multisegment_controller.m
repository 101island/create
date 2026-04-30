function result = nlarx_multisegment_controller(action, varargin)
%NLARX_MULTISEGMENT_CONTROLLER Design/simulate/run altitude control.
% Inputs to nlarx1 must be [actuator_output, altitude].
% Output of nlarx1 must be vertical speed, upward positive.

if nargin < 1 || strlength(string(action)) == 0
    action = "design";
end

opts = parseOptions(varargin{:});
model = loadModel(opts.modelFile);

switch lower(string(action))
    case "design"
        result = designController(model, opts);
    case "simulate"
        result = simulateSuite(model, defaultController(), opts);
    case "run"
        result = runOnline(model, defaultController(), opts);
    otherwise
        error("Unknown action: %s", string(action));
end
end

function opts = parseOptions(varargin)
opts = struct();
opts.modelFile = fullfile(fileparts(mfilename("fullpath")), "matlab1.mat");
opts.baseUrl = "http://127.0.0.1:8768";
opts.token = string(getenv("CC_AIRSHIP_BRIDGE_TOKEN"));
opts.alias = "TopThruster";
opts.target = 180;
opts.duration = 90;
opts.Ts = 0.2;
opts.logDir = fullfile(fileparts(mfilename("fullpath")), "data");
opts.dryRun = false;
opts.startHeight = [];

if mod(numel(varargin), 2) ~= 0
    error("Options must be name/value pairs.");
end
for i = 1:2:numel(varargin)
    name = char(varargin{i});
    opts.(name) = varargin{i + 1};
end
end

function model = loadModel(modelFile)
S = load(modelFile, "nlarx1");
if ~isfield(S, "nlarx1")
    error("nlarx1 not found in %s", modelFile);
end
model = S.nlarx1;
end

function ctrl = defaultController()
ctrl = struct();
ctrl.heightGrid = [80 100 120 140 160 180 200 220];
ctrl.hoverGrid = [4.0 4.5 5.25 5.75 6.25 7.0 7.35 7.60];
ctrl.outputMin = 0;
ctrl.outputMax = 15;
ctrl.maxStep = 0.25;
ctrl.integralLimit = 1.2;
ctrl.heightIntegralLimit = 12.0;
ctrl.speedIntegralLimit = 6.0;
ctrl.segments = [
    struct("hMin", 80,  "hMax", 120, "kh", 0.050, "khi", 0.010, "vMax", 0.35, "kv", 2.10, "ki", 0.012)
    struct("hMin", 120, "hMax", 170, "kh", 0.050, "khi", 0.009, "vMax", 0.40, "kv", 2.30, "ki", 0.014)
    struct("hMin", 170, "hMax", 220, "kh", 0.050, "khi", 0.008, "vMax", 0.50, "kv", 2.80, "ki", 0.014)
];
end

function result = designController(model, opts)
ctrl = defaultController();
suite = simulateSuite(model, ctrl, opts);
result = suite;
dispSummary(suite);
end

function suite = simulateSuite(model, ctrl, opts)
targets = [80 100 120 140 160 180 200 220];
starts = [90 130 170 210];
rows = [];
for target = targets
    for startHeight = starts
        sim = simulateClosedLoop(model, ctrl, target, startHeight, opts.duration, opts.Ts);
        rows = [rows; target, startHeight, sim.finalError, sim.maxOvershoot, sim.settlingTime, sim.maxAbsSpeed, sim.saturatedFraction]; %#ok<AGROW>
    end
end
suite = struct();
suite.controller = ctrl;
suite.table = array2table(rows, "VariableNames", ...
    ["target", "startHeight", "finalError", "maxOvershoot", "settlingTime", "maxAbsSpeed", "saturatedFraction"]);
end

function sim = simulateClosedLoop(model, ctrl, target, startHeight, duration, Ts)
n = floor(duration / Ts) + 1;
t = (0:n-1)' * Ts;
h = nan(n, 1);
v = nan(n, 1);
u = nan(n, 1);
vTarget = nan(n, 1);
h(1) = startHeight;
v(1) = 0;
u(1) = hoverFor(ctrl, h(1));
hInt = 0;
previousHeightError = target - h(1);
vInt = 0;

for k = 2:n
    seg = segmentFor(ctrl, h(k - 1));
    hErr = target - h(k - 1);
    if hErr * previousHeightError < 0
        hInt = 0;
    elseif abs(hErr) < 8
        hInt = clamp(hInt + hErr * Ts, -ctrl.heightIntegralLimit, ctrl.heightIntegralLimit);
    else
        hInt = 0.98 * hInt;
    end
    previousHeightError = hErr;
    vtRaw = seg.kh * hErr + seg.khi * hInt;
    vtLimit = min(seg.vMax, sqrt(max(0, 0.06 * abs(hErr))));
    vTarget(k - 1) = clamp(vtRaw, -vtLimit, vtLimit);

    vErr = vTarget(k - 1) - v(k - 1);
    vInt = clamp(vInt + vErr * Ts, -ctrl.speedIntegralLimit, ctrl.speedIntegralLimit);
    uRaw = hoverFor(ctrl, h(k - 1)) + seg.kv * vErr + seg.ki * vInt;
    uLimited = clamp(uRaw, ctrl.outputMin, ctrl.outputMax);
    u(k) = clamp(uLimited, u(k - 1) - ctrl.maxStep, u(k - 1) + ctrl.maxStep);

    v(k) = predictNextSpeed(model, v(max(1, k - 2)), v(k - 1), ...
        u(max(1, k - 2)), u(k - 1), h(max(1, k - 2)), h(k - 1));
    h(k) = h(k - 1) + Ts * v(k);
end
vTarget(end) = vTarget(end - 1);

err = target - h;
inside = abs(err) <= 0.1 & abs(v) <= 0.05;
settlingTime = NaN;
for k = 1:n
    if all(inside(k:end))
        settlingTime = t(k);
        break;
    end
end

sim = struct();
sim.t = t;
sim.h = h;
sim.v = v;
sim.u = u;
sim.vTarget = vTarget;
sim.finalError = err(end);
if startHeight < target
    sim.maxOvershoot = max(0, max(h - target));
else
    sim.maxOvershoot = max(0, max(target - h));
end
sim.settlingTime = settlingTime;
sim.maxAbsSpeed = max(abs(v));
sim.saturatedFraction = mean(u <= ctrl.outputMin + 1e-6 | u >= ctrl.outputMax - 1e-6);
end

function result = runOnline(~, ctrl, opts)
addpath(fileparts(mfilename("fullpath")));
if ~exist(opts.logDir, "dir")
    mkdir(opts.logDir);
end

y0 = cc_bridge_read(opts.baseUrl, opts.token, opts.alias);
if y0(4) ~= 1 || y0(6) ~= 1
    error("Bridge is not connected. connected=%g ok=%g", y0(4), y0(6));
end

target = opts.target;
if target < 80 || target > 220
    error("Target %.3f is outside 80..220.", target);
end

u0 = y0(3);
if ~isfinite(u0)
    u0 = hoverFor(ctrl, y0(1));
end
cleanup = onCleanup(@() cc_bridge_write(u0, opts.baseUrl, opts.token, opts.alias)); %#ok<NASGU>

n = floor(opts.duration / opts.Ts) + 1;
logData = nan(n, 12);
vInt = 0;
hInt = 0;
previousHeightError = [];
uPrev = u0;
t0 = tic;

for k = 1:n
    loopStart = tic;
    y = cc_bridge_read(opts.baseUrl, opts.token, opts.alias);
    h = y(1);
    v = y(2);
    seg = segmentFor(ctrl, h);
    hErr = target - h;
    if isempty(previousHeightError)
        previousHeightError = hErr;
    end
    if hErr * previousHeightError < 0
        hInt = 0;
    elseif abs(hErr) < 8
        hInt = clamp(hInt + hErr * opts.Ts, -ctrl.heightIntegralLimit, ctrl.heightIntegralLimit);
    else
        hInt = 0.98 * hInt;
    end
    previousHeightError = hErr;
    vtRaw = seg.kh * hErr + seg.khi * hInt;
    vtLimit = min(seg.vMax, sqrt(max(0, 0.06 * abs(hErr))));
    vt = clamp(vtRaw, -vtLimit, vtLimit);
    vErr = vt - v;
    vInt = clamp(vInt + vErr * opts.Ts, -ctrl.speedIntegralLimit, ctrl.speedIntegralLimit);
    uRaw = hoverFor(ctrl, h) + seg.kv * vErr + seg.ki * vInt;
    uCmd = clamp(uRaw, ctrl.outputMin, ctrl.outputMax);
    uCmd = clamp(uCmd, uPrev - ctrl.maxStep, uPrev + ctrl.maxStep);

    if opts.dryRun
        okWrite = 1;
    else
        okWrite = cc_bridge_write(uCmd, opts.baseUrl, opts.token, opts.alias);
    end
    uPrev = uCmd;
    simT = toc(t0);
    logData(k, :) = [simT, y(5), target, h, v, vt, hErr, uCmd, y(3), y(4), y(6), okWrite];
    pause(max(0, opts.Ts - toc(loopStart)));
end

cc_bridge_write(u0, opts.baseUrl, opts.token, opts.alias);
T = array2table(logData, "VariableNames", ...
    ["sim_t", "cc_t", "target", "height", "vertical_speed", "speed_target", ...
     "height_error", "u_cmd", "u_actual", "connected", "read_ok", "write_ok"]);
file = fullfile(opts.logDir, "nlarx_control_" + datestr(now, "yyyymmdd_HHMMSS") + ".csv");
writetable(T, file);

result = struct();
result.logFile = file;
result.table = T;
result.finalError = T.height_error(end);
result.maxOvershoot = max(0, max(T.height - target));
result.minHeight = min(T.height);
result.maxHeight = max(T.height);
result.maxAbsSpeed = max(abs(T.vertical_speed));
disp(result);
end

function vNext = predictNextSpeed(model, vKm1, vK, uKm1, uK, hKm1, hK)
% idnlarx/predict requires more samples than the regressor count. The last
% row is the prediction target; preceding rows provide repeated local state.
yData = [vKm1; vK; vK; vK; vK; vK; vK; 0];
uData = [
    uKm1 hKm1
    uK hK
    uK hK
    uK hK
    uK hK
    uK hK
    uK hK
    uK hK
];
z = iddata(yData, uData, model.Ts);
z.InputName = model.InputName;
z.OutputName = model.OutputName;
yp = predict(model, z, 1);
y = yp.OutputData;
vNext = y(end);
end

function seg = segmentFor(ctrl, h)
for i = 1:numel(ctrl.segments)
    seg = ctrl.segments(i);
    if h >= seg.hMin && h < seg.hMax
        return;
    end
end
if h < ctrl.segments(1).hMin
    seg = ctrl.segments(1);
else
    seg = ctrl.segments(end);
end
end

function u = hoverFor(ctrl, h)
u = interp1(ctrl.heightGrid, ctrl.hoverGrid, h, "pchip", "extrap");
u = clamp(u, ctrl.outputMin, ctrl.outputMax);
end

function value = clamp(value, minValue, maxValue)
value = min(max(value, minValue), maxValue);
end

function dispSummary(suite)
T = suite.table;
disp(T);
validSettling = T.settlingTime(~isnan(T.settlingTime));
fprintf("max |final error| = %.4f\\n", max(abs(T.finalError)));
fprintf("max overshoot = %.4f\\n", max(T.maxOvershoot));
if isempty(validSettling)
    fprintf("no case settled to |error|<=0.1 and |v|<=0.05 within duration\\n");
else
    fprintf("max settling time = %.2f s\\n", max(validSettling));
end
fprintf("max |speed| = %.4f\\n", max(T.maxAbsSpeed));
fprintf("max saturation fraction = %.4f\\n", max(T.saturatedFraction));
end
