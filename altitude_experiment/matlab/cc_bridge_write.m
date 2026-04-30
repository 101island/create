function ok = cc_bridge_write(command, baseUrl, token, alias)
%CC_BRIDGE_WRITE Pass an actuator command through the HTTP bridge.

if nargin < 2
    baseUrl = "";
end
if nargin < 3
    token = "";
end
if nargin < 4
    alias = "";
end

cfg = cc_bridge_config(baseUrl, token, alias);

ok = 0;
try
    opt = bridgeOptions(cfg);
    url = cfg.baseUrl + "/command?alias=" + queryValue(cfg.alias) + ...
        "&command=" + queryValue(num2str(command, 17));
    r = webread(url, opt);
    if isstruct(r) && isfield(r, "ok")
        ok = double(r.ok == true);
    end
catch
    ok = 0;
end
end

function value = queryValue(value)
value = char(string(value));
value = strrep(value, "%", "%25");
value = strrep(value, " ", "%20");
value = strrep(value, "&", "%26");
value = strrep(value, "=", "%3D");
value = strrep(value, "?", "%3F");
end

function opt = bridgeOptions(cfg)
if strlength(cfg.token) == 0
    opt = weboptions("MediaType", "application/json", "Timeout", cfg.timeout);
else
    opt = weboptions("MediaType", "application/json", "Timeout", cfg.timeout, ...
        "HeaderFields", ["X-Bridge-Token", cfg.token]);
end
end
