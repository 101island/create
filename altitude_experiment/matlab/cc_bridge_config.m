function cfg = cc_bridge_config(baseUrl, token, alias)
%CC_BRIDGE_CONFIG Shared defaults for Simulink/MATLAB bridge passthrough.

if nargin < 1 || strlength(string(baseUrl)) == 0
    baseUrl = string(getenv("CC_AIRSHIP_BRIDGE_URL"));
end
if strlength(string(baseUrl)) == 0
    baseUrl = "http://127.0.0.1:8768";
end

if nargin < 2
    token = string(getenv("CC_AIRSHIP_BRIDGE_TOKEN"));
end

if nargin < 3 || strlength(string(alias)) == 0
    alias = "TopThruster";
end

cfg = struct();
cfg.baseUrl = string(baseUrl);
cfg.token = string(token);
cfg.alias = string(alias);
cfg.timeout = 2;

cfg.heightFrame = struct();
% Measured on airship_exp1: altimeter_height ~= sable_pose_y - 2.60.
% Use this when an experiment command wants to set the altimeter height.
cfg.heightFrame.poseYOffsetFromAltitude = 2.60;
cfg.heightFrame.altitudeOffsetFromPoseY = -2.60;
end
