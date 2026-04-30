#!/usr/bin/env python3
"""Calibrate hover feedforward levels at fixed heights.

For each candidate output level:
1. Command the actuator and wait for gas/lift to settle.
2. Teleport the named Sable/Create Simulated vehicle to the test height.
3. Observe vertical speed over a short window.

The script keeps the server at normal tick rate. It only uses HTTP bridge and
RCON; it does not depend on MATLAB.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import shlex
import subprocess
import time
import urllib.request
from datetime import datetime
from pathlib import Path


PATH_PREFIX = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
POSITION_RE = re.compile(r"Position:\s*([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)")


def clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


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

    def command(self, output: float) -> bool:
        data = self.request(f"/command?alias={self.alias}&command={output:.6f}")
        return bool(data.get("ok"))

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


def read_vehicle_xz(name: str, ssh_target: str, container: str) -> tuple[float, float]:
    output = run_rcon(f"sable info @e[name={name}]", ssh_target, container)
    match = POSITION_RE.search(output)
    if not match:
        raise RuntimeError("Could not parse Sable position from RCON output.")
    return float(match.group(1)), float(match.group(3))


def teleport_height(name: str, height: float, x: float, z: float, ssh_target: str, container: str) -> None:
    run_rcon(f"sable teleport @e[name={name}] {x:.12g} {height:.12g} {z:.12g}", ssh_target, container)


def interpolate_hover(height: float) -> float:
    points = [
        (80, 4.00),
        (100, 4.50),
        (120, 5.25),
        (140, 5.75),
        (160, 6.00),
        (180, 6.50),
        (200, 7.05),
        (220, 7.60),
    ]
    if height <= points[0][0]:
        left, right = points[0], points[1]
    elif height >= points[-1][0]:
        left, right = points[-2], points[-1]
    else:
        right_index = next(i for i in range(1, len(points)) if height <= points[i][0])
        left, right = points[right_index - 1], points[right_index]
    ratio = (height - left[0]) / (right[0] - left[0])
    return left[1] + (right[1] - left[1]) * ratio


def hold_output(bridge: Bridge, output: float, duration: float, period: float) -> None:
    start = time.monotonic()
    while time.monotonic() - start < duration:
        bridge.command(output)
        time.sleep(period)


def observe(bridge: Bridge, output: float, duration: float, period: float) -> list[dict]:
    samples = []
    start = time.monotonic()
    while time.monotonic() - start < duration:
        bridge.command(output)
        sample = bridge.state()
        sample["observe_t"] = time.monotonic() - start
        samples.append(sample)
        time.sleep(period)
    return samples


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else float("nan")


def test_output(
    bridge: Bridge,
    args: argparse.Namespace,
    height: float,
    output: float,
    x: float,
    z: float,
    writer: csv.writer,
) -> dict:
    print(f"height={height:.1f} output={output:.3f}: precharge {args.precharge:.1f}s", flush=True)
    hold_output(bridge, output, args.precharge, args.period)

    teleport_height(args.name, height, x, z, args.ssh_target, args.container)
    time.sleep(args.reset_settle)
    samples = observe(bridge, output, args.observe, args.period)
    speeds = [sample["speed"] for sample in samples]
    heights = [sample["height"] for sample in samples]
    outputs = [sample["output"] for sample in samples]
    avg_speed = mean(speeds)

    for sample in samples:
        writer.writerow([
            datetime.now().isoformat(timespec="milliseconds"),
            height,
            output,
            sample["observe_t"],
            sample["cc_t"],
            sample["height"],
            sample["speed"],
            sample["output"],
            int(sample["connected"]),
        ])

    result = {
        "height": height,
        "output": output,
        "avg_speed": avg_speed,
        "min_speed": min(speeds),
        "max_speed": max(speeds),
        "height_start": heights[0],
        "height_end": heights[-1],
        "height_drift": heights[-1] - heights[0],
        "avg_actual_output": mean(outputs),
        "score": abs(avg_speed),
    }
    print(
        f"  avg_v={avg_speed:+.4f} min_v={result['min_speed']:+.4f} "
        f"max_v={result['max_speed']:+.4f} dh={result['height_drift']:+.3f} "
        f"act={result['avg_actual_output']:.3f}",
        flush=True,
    )
    return result


def candidate_outputs(center: float, span: float, step: float) -> list[float]:
    count = int(round(span / step))
    values = [center + index * step for index in range(-count, count + 1)]
    values = [round(clamp(value, 0, 15), 6) for value in values]
    return sorted(set(values))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=os.environ.get("CC_AIRSHIP_BRIDGE_URL", "http://127.0.0.1:8768"))
    parser.add_argument("--token", default=os.environ.get("CC_AIRSHIP_BRIDGE_TOKEN", ""))
    parser.add_argument("--alias", default="TopThruster")
    parser.add_argument("--name", default="airship_exp1")
    parser.add_argument("--ssh-target", default="mac")
    parser.add_argument("--container", default="mc-create-aeronautics")
    parser.add_argument("--heights", nargs="+", type=float, default=[80, 100, 120, 140, 160, 180, 200, 220])
    parser.add_argument("--center-offset", type=float, default=0.0)
    parser.add_argument("--span", type=float, default=0.6)
    parser.add_argument("--step", type=float, default=0.2)
    parser.add_argument("--precharge", type=float, default=25.0)
    parser.add_argument("--reset-settle", type=float, default=1.5)
    parser.add_argument("--observe", type=float, default=8.0)
    parser.add_argument("--period", type=float, default=0.2)
    parser.add_argument("--log-dir", default=str(Path(__file__).resolve().parent / "data"))
    parser.add_argument("--stop-output", type=float, default=None)
    args = parser.parse_args()

    bridge = Bridge(args.base_url, args.token, args.alias)
    state = bridge.state()
    if not state["connected"]:
        raise SystemExit("Bridge is not connected.")

    tick_query = run_rcon("tick query", args.ssh_target, args.container)
    if "Target tick rate: 20.0" not in tick_query:
        raise SystemExit("Server tick rate is not 20.0; restore it before calibration.")

    x, z = read_vehicle_xz(args.name, args.ssh_target, args.container)

    log_dir = Path(args.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    sample_file = log_dir / f"hover_calibration_samples_{stamp}.csv"
    summary_file = log_dir / f"hover_calibration_summary_{stamp}.csv"

    summaries = []
    try:
        with sample_file.open("w", newline="", encoding="utf-8") as sample_handle:
            writer = csv.writer(sample_handle)
            writer.writerow([
                "wall_time",
                "test_height",
                "command_output",
                "observe_t",
                "cc_t",
                "height",
                "vertical_speed",
                "actual_output",
                "connected",
            ])
            for height in args.heights:
                center = interpolate_hover(height) + args.center_offset
                results = []
                for output in candidate_outputs(center, args.span, args.step):
                    results.append(test_output(bridge, args, height, output, x, z, writer))
                best = min(results, key=lambda item: item["score"])
                summaries.append(best)
                bridge.command(best["output"])
                print(
                    f"BEST height={height:.1f}: output={best['output']:.3f} "
                    f"avg_v={best['avg_speed']:+.4f}",
                    flush=True,
                )
    finally:
        if args.stop_output is not None:
            bridge.command(args.stop_output)

    with summary_file.open("w", newline="", encoding="utf-8") as summary_handle:
        fieldnames = [
            "height",
            "output",
            "avg_speed",
            "min_speed",
            "max_speed",
            "height_start",
            "height_end",
            "height_drift",
            "avg_actual_output",
            "score",
        ]
        writer = csv.DictWriter(summary_handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summaries)

    print(f"samples={sample_file}", flush=True)
    print(f"summary={summary_file}", flush=True)
    print("hover levels:", flush=True)
    for item in summaries:
        print(f"  {{ altitude = {item['height']:.0f}, level = {item['output']:.3f} }},", flush=True)


if __name__ == "__main__":
    main()
