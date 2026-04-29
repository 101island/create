% Altitude experiment CSV import for MATLAB System Identification.
% Copy altitude_id.csv or altitude_log.csv from the ComputerCraft computer to
% this folder first.

if exist("altitude_id.csv", "file")
    file = "altitude_id.csv";
else
    file = "altitude_log.csv";
end
T = readtable(file);

required = ["t", "output_command", "altitude"];
T = rmmissing(T, "DataVariables", required);

% ComputerCraft logs absolute epoch seconds. Convert to relative seconds.
t = T.t - T.t(1);
Ts = median(diff(t), "omitnan");

% Basic SISO dataset: actuator command -> altitude.
% For open-loop identification, prefer data collected in speed/manual mode or
% from deliberate output steps. Closed-loop data can still be inspected, but
% model estimates may be biased by controller feedback.
u = T.output_command;
y = T.altitude;

disp("Loaded file: " + file);
disp("Estimated sample time Ts = " + Ts + " s");

figure;
subplot(3, 1, 1);
plot(t, T.altitude);
grid on;
ylabel("altitude");

subplot(3, 1, 2);
plot(t, T.output_command);
grid on;
ylabel("output");

subplot(3, 1, 3);
if ismember("speed", string(T.Properties.VariableNames))
    plot(t, T.speed);
    ylabel("speed");
else
    plot(t, [0; diff(T.altitude) ./ diff(t)]);
    ylabel("d altitude");
end
grid on;
xlabel("time (s)");

if exist("iddata", "file") ~= 2 || exist("tfest", "file") ~= 2
    warning("System Identification Toolbox functions iddata/tfest were not found. Import and plotting completed.");
    return;
end

data = iddata(y, u, Ts, ...
    "TimeUnit", "seconds", ...
    "InputName", "actuator_command", ...
    "OutputName", "altitude");

data = detrend(data);

figure;
plot(data);
grid on;
title("Altitude experiment identification data");

% Starter models. Adjust orders after inspecting residuals and validation fit.
tf1 = tfest(data, 1, 0);
tf2 = tfest(data, 2, 1);

figure;
compare(data, tf1, tf2);
grid on;
title("Model comparison");

disp(tf1);
disp(tf2);

% Segment helper for the current altitude bands.
segments = {
    "low",  T.altitude < 128;
    "mid",  T.altitude >= 128 & T.altitude < 256;
    "high", T.altitude >= 256
};

for i = 1:size(segments, 1)
    name = segments{i, 1};
    idx = segments{i, 2};
    if nnz(idx) > 20
        ti = T.t(idx) - T.t(find(idx, 1));
        Tsi = median(diff(ti), "omitnan");
        di = iddata(T.altitude(idx), T.output_command(idx), Tsi, ...
            "TimeUnit", "seconds", ...
            "InputName", "actuator_command", ...
            "OutputName", "altitude");
        di = detrend(di);
        sys = tfest(di, 2, 0);
        fprintf("\nSegment %s, samples=%d, Ts=%.4f\n", name, nnz(idx), Tsi);
        disp(sys);
        damp(sys);
    end
end
