#!/usr/bin/env python3
"""Online segmented cascade PID sweep through the MATLAB bridge.

This is an experiment runner, not the final CraftOS controller. It mirrors the
Lua-side tuning constants so the whole 80..220 band can be tested quickly from
the PC bridge.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import shlex
import subprocess
import time
import urllib.request
from datetime import datetime
from pathlib import Path


PATH_PREFIX = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def run_rcon(command: str, ssh_target: str, container: str) -> str:
    remote = f"{PATH_PREFIX}; docker exec {shlex.quote(container)} rcon-cli {shlex.quote(command)}"
    result = subprocess.run(
        ["ssh", ssh_target, remote],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stdout.strip())
    return result.stdout


class Bridge:
    def __init__(self, base_url: str, token: str, alias: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.alias = alias

    def request(self, path: str) -> dict:
        headers = {"X-Bridge-Token": self.token} if self.token else {}
        req = urllib.request.Request(self.base_url + path, headers=headers)
        with urllib.request.urlopen(req, timeout=2) as response:
            return json.loads(response.read().decode("utf-8"))

    def state(self) -> dict:
        data = self.request("/state")
        state = data.get("state") or {}
        sensors = state.get("sensors") or {}
        actuators = state.get("actuators") or {}
        return {
            "connected": bool(data.get("connected")),
            "cc_t": float(state.get("t") or float("nan")),
            "height": float(sensors.get("altitude")),
            "speed": -float(sensors.get("down") or 0.0),
            "output": float(actuators.get(self.alias) if actuators.get(self.alias) is not None else float("nan")),
        }

    def command(self, output: float) -> bool:
        path = f"/command?alias={self.alias}&command={output:.6f}"
        return bool(self.request(path).get("ok"))


class SegmentedCascade:
    height_points = [80, 100, 120, 140, 160, 180, 200, 220]
    hover_points = [4.00, 4.50, 5.25, 5.75, 6.25, 7.00, 7.35, 7.60]

    def __init__(self) -> None:
        self.height_integral = 0.0
        self.speed_integral = 0.0
        self.previous_height_error: float | None = None
        self.previous_output: float | None = None
        self.filtered_speed: float | None = None
        self.speed_filter_alpha = 0.35

    def reset_target(self) -> None:
        self.height_integral = 0.0
        self.speed_integral = 0.0
        self.previous_height_error = None

    def hover(self, height: float) -> float:
        xs = self.height_points
        ys = self.hover_points
        if height <= xs[0]:
            index = 1
        elif height >= xs[-1]:
            index = len(xs) - 1
        else:
            index = next(i for i in range(1, len(xs)) if height <= xs[i])
        x0, x1 = xs[index - 1], xs[index]
        y0, y1 = ys[index - 1], ys[index]
        return clamp(y0 + (y1 - y0) * (height - x0) / (x1 - x0), 0, 15)

    @staticmethod
    def segment(height: float) -> dict:
        if height < 120:
            return {"kh": 0.050, "khi": 0.010, "vmax": 0.25, "kv": 1.40, "ki": 0.012, "cmax": 0.90}
        if height < 170:
            return {"kh": 0.050, "khi": 0.009, "vmax": 0.30, "kv": 1.50, "ki": 0.014, "cmax": 1.00}
        return {"kh": 0.050, "khi": 0.008, "vmax": 0.35, "kv": 1.60, "ki": 0.014, "cmax": 1.20}

    def update(self, target: float, height: float, speed: float, dt: float) -> dict:
        if self.filtered_speed is None:
            self.filtered_speed = speed
        else:
            self.filtered_speed += self.speed_filter_alpha * (speed - self.filtered_speed)
        control_speed = self.filtered_speed
        error = target - height
        if self.previous_height_error is None:
            self.previous_height_error = error
        if error * self.previous_height_error < 0:
            self.height_integral = 0.0
        elif abs(error) < 8:
            self.height_integral = clamp(self.height_integral + error * dt, -12, 12)
        else:
            self.height_integral *= 0.98
        self.previous_height_error = error

        seg = self.segment(height)
        raw_speed_target = seg["kh"] * error + seg["khi"] * self.height_integral
        speed_limit = min(seg["vmax"], math.sqrt(max(0.0, 0.06 * abs(error))))
        speed_target = clamp(raw_speed_target, -speed_limit, speed_limit)

        speed_error = speed_target - control_speed
        if abs(speed_error) < 0.8:
            self.speed_integral = clamp(self.speed_integral + speed_error * dt, -4, 4)
        else:
            self.speed_integral *= 0.98

        hover = self.hover(height)
        correction = clamp(seg["kv"] * speed_error + seg["ki"] * self.speed_integral, -seg["cmax"], seg["cmax"])
        raw_output = hover + correction
        output = clamp(raw_output, 0, 15)
        if self.previous_output is not None:
            output = clamp(output, self.previous_output - 0.20, self.previous_output + 0.20)
        self.previous_output = output

        return {
            "height_error": error,
            "speed_target": speed_target,
            "control_speed": control_speed,
            "height_integral": self.height_integral,
            "speed_error": speed_error,
            "hover": hover,
            "raw_output": raw_output,
            "output": output,
        }


def run_target(bridge: Bridge, controller: SegmentedCascade, target: float, args: argparse.Namespace, writer: csv.writer, wall_period: float) -> dict:
    controller.reset_target()
    start = bridge.state()
    print(f"target={target:.1f} start h={start['height']:.3f} v={start['speed']:.3f} u={start['output']:.3f}", flush=True)
    target_start_time = time.monotonic()
    stable_count = 0
    rows = []
    next_print = 0.0

    for _ in range(int(args.max_target_time / args.period) + 1):
        loop_start = time.monotonic()
        elapsed = loop_start - target_start_time
        game_elapsed = elapsed * args.tick_rate / 20.0 if args.tick_rate > 0 else elapsed
        sample = bridge.state()
        control = controller.update(target, sample["height"], sample["speed"], args.period)
        write_ok = bridge.command(control["output"])

        row = [
            datetime.now().isoformat(timespec="milliseconds"),
            target,
            elapsed,
            game_elapsed,
            args.tick_rate,
            sample["cc_t"],
            sample["height"],
            sample["speed"],
            control["height_error"],
            control["speed_target"],
            control["control_speed"],
            control["height_integral"],
            control["hover"],
            control["raw_output"],
            control["output"],
            sample["output"],
            int(sample["connected"]),
            int(write_ok),
        ]
        writer.writerow(row)
        rows.append(row)

        if abs(control["height_error"]) <= args.error_band and abs(sample["speed"]) <= args.speed_band:
            stable_count += 1
        else:
            stable_count = 0

        if elapsed >= next_print:
            print(
                f"  t={game_elapsed:6.1f}g/{elapsed:5.1f}w h={sample['height']:8.3f} v={sample['speed']:7.3f} "
                f"vf={control['control_speed']:7.3f} e={control['height_error']:8.3f} vt={control['speed_target']:6.3f} "
                f"u={control['output']:5.2f} act={sample['output']:5.2f}",
                flush=True,
            )
            next_print += args.print_period

        if stable_count >= int(args.stable_time / args.period):
            print(f"  stable target={target:.1f} at game_t={game_elapsed:.1f} wall_t={elapsed:.1f}", flush=True)
            break
        if sample["height"] < args.min_height or sample["height"] > args.max_height or abs(sample["speed"]) > args.max_abs_speed:
            print(f"  SAFETY_STOP h={sample['height']:.3f} v={sample['speed']:.3f}", flush=True)
            break

        time.sleep(max(0.0, wall_period - (time.monotonic() - loop_start)))

    heights = [float(row[4]) for row in rows]
    speeds = [float(row[5]) for row in rows]
    errors = [float(row[6]) for row in rows]
    final = rows[-1]
    direction = 1 if start["height"] < target else -1
    if direction > 0:
        overshoot = max(0.0, max(heights) - target)
    else:
        overshoot = max(0.0, target - min(heights))
    summary = {
        "target": target,
        "start_height": start["height"],
        "final_height": float(final[4]),
        "final_speed": float(final[5]),
        "final_error": float(final[6]),
        "overshoot": overshoot,
        "min_height": min(heights),
        "max_height": max(heights),
        "max_abs_speed": max(abs(value) for value in speeds),
        "wall_duration": float(final[2]),
        "game_duration": float(final[3]),
        "max_abs_error": max(abs(value) for value in errors),
    }
    print(
        f"  summary final_h={summary['final_height']:.3f} err={summary['final_error']:.3f} "
        f"overshoot={summary['overshoot']:.3f} max|v|={summary['max_abs_speed']:.3f}",
        flush=True,
    )
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=os.environ.get("CC_AIRSHIP_BRIDGE_URL", "http://127.0.0.1:8768"))
    parser.add_argument("--token", default=os.environ.get("CC_AIRSHIP_BRIDGE_TOKEN", ""))
    parser.add_argument("--alias", default="TopThruster")
    parser.add_argument("--targets", nargs="+", type=float, default=[180, 160, 140, 120, 100, 80, 120, 160, 200, 220])
    parser.add_argument("--period", type=float, default=0.2)
    parser.add_argument("--max-target-time", type=float, default=120.0)
    parser.add_argument("--stable-time", type=float, default=8.0)
    parser.add_argument("--error-band", type=float, default=0.10)
    parser.add_argument("--speed-band", type=float, default=0.05)
    parser.add_argument("--print-period", type=float, default=5.0)
    parser.add_argument("--tick-rate", type=float, default=20.0)
    parser.add_argument("--restore-tick-rate", type=float, default=20.0)
    parser.add_argument("--ssh-target", default="mac")
    parser.add_argument("--container", default="mc-create-aeronautics")
    parser.add_argument("--min-height", type=float, default=70.0)
    parser.add_argument("--max-height", type=float, default=240.0)
    parser.add_argument("--max-abs-speed", type=float, default=5.0)
    parser.add_argument("--log-dir", default=str(Path(__file__).resolve().parent / "data"))
    args = parser.parse_args()

    log_dir = Path(args.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"segment_sweep_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    summary_file = log_dir / f"segment_sweep_summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"

    bridge = Bridge(args.base_url, args.token, args.alias)
    controller = SegmentedCascade()
    wall_period = args.period
    if args.tick_rate > 0:
        wall_period = args.period * 20.0 / args.tick_rate

    if args.tick_rate != args.restore_tick_rate:
        print(run_rcon(f"tick rate {args.tick_rate:g}", args.ssh_target, args.container), end="", flush=True)

    try:
        with log_file.open("w", newline="", encoding="utf-8") as log_handle:
            writer = csv.writer(log_handle)
            writer.writerow([
                "wall_time",
            "target",
            "target_wall_t",
            "target_game_t",
            "tick_rate",
            "cc_t",
                "height",
                "vertical_speed",
                "height_error",
                "speed_target",
                "control_speed",
                "height_integral",
                "hover",
                "raw_output",
                "output_command",
                "output_actual",
                "connected",
                "write_ok",
            ])
            summaries = [run_target(bridge, controller, target, args, writer, wall_period) for target in args.targets]
    finally:
        if args.tick_rate != args.restore_tick_rate:
            print(run_rcon(f"tick rate {args.restore_tick_rate:g}", args.ssh_target, args.container), end="", flush=True)

    with summary_file.open("w", newline="", encoding="utf-8") as summary_handle:
        names = list(summaries[0].keys())
        writer = csv.DictWriter(summary_handle, fieldnames=names)
        writer.writeheader()
        writer.writerows(summaries)

    print(f"log={log_file}", flush=True)
    print(f"summary={summary_file}", flush=True)


if __name__ == "__main__":
    main()
