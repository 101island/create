function y = sable_set_height_trigger(height, trigger, name, x, z, sshTarget, container, poseYOffsetFromAltitude)
%SABLE_SET_HEIGHT_TRIGGER Set target altimeter height on a trigger rising edge.
% y = [ok; fired; status]

persistent lastTrigger
if isempty(lastTrigger)
    lastTrigger = false;
end

if nargin < 2
    trigger = 0;
end
if nargin < 3 || strlength(string(name)) == 0
    name = "airship_exp1";
end
if nargin < 6 || strlength(string(sshTarget)) == 0
    sshTarget = "mac";
end
if nargin < 7 || strlength(string(container)) == 0
    container = "mc-create-aeronautics";
end
if nargin < 8
    poseYOffsetFromAltitude = [];
end

y = [1; 0; 0];
currentTrigger = trigger > 0;
fired = currentTrigger && ~lastTrigger;
lastTrigger = currentTrigger;

if ~fired
    return;
end

y(2) = 1;

try
    if nargin < 4
        x = [];
    end
    if nargin < 5
        z = [];
    end
    result = sable_set_height_once(height, name, x, z, sshTarget, container, poseYOffsetFromAltitude);
    y(1) = result(1);
    y(3) = result(2);
catch
    y(1) = 0;
    y(3) = -1;
end
end
