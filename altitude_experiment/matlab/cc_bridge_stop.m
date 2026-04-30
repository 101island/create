function ok = cc_bridge_stop(baseUrl, token, alias)
%CC_BRIDGE_STOP Send zero output to the actuator.

if nargin < 1
    baseUrl = "";
end
if nargin < 2
    token = "";
end
if nargin < 3
    alias = "";
end

ok = cc_bridge_write(0, baseUrl, token, alias);
end
