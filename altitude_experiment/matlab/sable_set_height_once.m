function y = sable_set_height_once(height, name, x, z, sshTarget, container, poseYOffsetFromAltitude)
%SABLE_SET_HEIGHT_ONCE Set target altimeter height once through ssh + rcon-cli.
% y = [ok; status]
%
% The input height is the altitude sensor reading target. Sable teleport uses
% sublevel pose Y, so this function applies poseYOffsetFromAltitude.

if nargin < 2 || strlength(string(name)) == 0
    name = "airship_exp1";
end
if nargin < 5 || strlength(string(sshTarget)) == 0
    sshTarget = "mac";
end
if nargin < 6 || strlength(string(container)) == 0
    container = "mc-create-aeronautics";
end
if nargin < 7 || isempty(poseYOffsetFromAltitude)
    cfg = cc_bridge_config();
    poseYOffsetFromAltitude = cfg.heightFrame.poseYOffsetFromAltitude;
end

y = [0; -1];
poseHeight = NaN;

try
    validateattributes(height, {'numeric'}, {'scalar', 'finite'});
    validateattributes(poseYOffsetFromAltitude, {'numeric'}, {'scalar', 'finite'});
    poseHeight = height + poseYOffsetFromAltitude;
    name = string(name);
    sshTarget = string(sshTarget);
    container = string(container);
    validateToken(name, "name");
    validateToken(sshTarget, "sshTarget");
    validateToken(container, "container");

    if nargin < 3 || isempty(x) || nargin < 4 || isempty(z)
        [x, z] = readCurrentXZ(name, sshTarget, container);
    else
        validateattributes(x, {'numeric'}, {'scalar', 'finite'});
        validateattributes(z, {'numeric'}, {'scalar', 'finite'});
    end

    rconCommand = sprintf("sable teleport @e[name=%s] %.12g %.12g %.12g", ...
        char(name), x, poseHeight, z);
    command = makeRconSshCommand(sshTarget, container, rconCommand);

    [status, output] = system(command);
    y(1) = double(status == 0);
    y(2) = double(status);
    assignin("base", "sable_last_result", struct( ...
        "ok", logical(status == 0), ...
        "status", status, ...
        "height", height, ...
        "poseHeight", poseHeight, ...
        "poseYOffsetFromAltitude", poseYOffsetFromAltitude, ...
        "x", x, ...
        "z", z, ...
        "output", string(output), ...
        "command", string(command)));
catch err
    y = [0; -1];
    assignin("base", "sable_last_result", struct( ...
        "ok", false, ...
        "status", -1, ...
        "height", height, ...
        "poseHeight", poseHeight, ...
        "poseYOffsetFromAltitude", poseYOffsetFromAltitude, ...
        "x", NaN, ...
        "z", NaN, ...
        "output", string(getReport(err, "extended", "hyperlinks", "off")), ...
        "command", ""));
end
end

function [x, z] = readCurrentXZ(name, sshTarget, container)
rconCommand = sprintf("sable info @e[name=%s]", char(name));
command = makeRconSshCommand(sshTarget, container, rconCommand);
[status, output] = system(command);
if status ~= 0
    error("sable_set_height_once:InfoFailed", "sable info failed.");
end

tokens = regexp(output, "Position:\s*([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)", "tokens", "once");
if isempty(tokens)
    error("sable_set_height_once:ParseFailed", "Could not parse sable position.");
end

x = str2double(tokens{1});
z = str2double(tokens{3});
if ~isfinite(x) || ~isfinite(z)
    error("sable_set_height_once:ParseFailed", "Invalid sable position.");
end
end

function command = makeRconSshCommand(sshTarget, container, rconCommand)
remoteCommand = sprintf("export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; docker exec %s rcon-cli '%s'", ...
    char(container), char(rconCommand));
command = sprintf('ssh %s "%s"', char(sshTarget), remoteCommand);
end

function validateToken(value, label)
if isempty(regexp(char(value), "^[A-Za-z0-9_.:@-]+$", "once"))
    error("Invalid %s.", label);
end
end
