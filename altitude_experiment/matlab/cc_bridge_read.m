function y = cc_bridge_read(baseUrl, token, alias)
%CC_BRIDGE_READ Read bridge state as a fixed numeric vector.
% y = [altitude; vertical_speed; actuator_output; connected; cc_t; ok]

if nargin < 1
    baseUrl = "";
end
if nargin < 2
    token = "";
end
if nargin < 3
    alias = "";
end

cfg = cc_bridge_config(baseUrl, token, alias);

y = nan(6, 1);
y(6) = 0;

try
    opt = bridgeOptions(cfg);
    r = webread(cfg.baseUrl + "/state", opt);
    state = structField(r, "state");
    sensors = structField(state, "sensors");
    actuators = structField(state, "actuators");

    altitude = valueField(sensors, "altitude", NaN);
    down = valueField(sensors, "down", NaN);

    y(1) = altitude;
    y(2) = -down;
    y(3) = valueField(actuators, char(cfg.alias), NaN);
    y(4) = double(valueField(r, "connected", false));
    y(5) = valueField(state, "t", NaN);
    y(6) = 1;
catch
    y(6) = 0;
end
end

function opt = bridgeOptions(cfg)
if strlength(cfg.token) == 0
    opt = weboptions("MediaType", "application/json", "Timeout", cfg.timeout);
else
    opt = weboptions("MediaType", "application/json", "Timeout", cfg.timeout, ...
        "HeaderFields", ["X-Bridge-Token", cfg.token]);
end
end

function out = structField(source, field)
out = struct();
if isstruct(source) && isfield(source, field) && isstruct(source.(field))
    out = source.(field);
end
end

function out = valueField(source, field, fallback)
out = fallback;
if isstruct(source) && isfield(source, field)
    out = source.(field);
end
end
