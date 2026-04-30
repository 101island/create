#!/usr/bin/env python3
"""Small RCON helper for Minecraft tick-rate experiments."""

from __future__ import annotations

import argparse
import shlex
import subprocess
import time


PATH_PREFIX = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"


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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["query", "rate", "sprint", "restore"])
    parser.add_argument("value", nargs="?")
    parser.add_argument("--ssh-target", default="mac")
    parser.add_argument("--container", default="mc-create-aeronautics")
    parser.add_argument("--duration", type=float, default=0)
    parser.add_argument("--restore-rate", type=float, default=20.0)
    args = parser.parse_args()

    if args.command == "query":
        print(run_rcon("tick query", args.ssh_target, args.container), end="")
        return

    if args.command == "restore":
        print(run_rcon(f"tick rate {args.restore_rate:g}", args.ssh_target, args.container), end="")
        print(run_rcon("tick query", args.ssh_target, args.container), end="")
        return

    if args.command == "rate":
        if args.value is None:
            raise SystemExit("rate requires a tick rate value")
        rate = float(args.value)
        print(run_rcon(f"tick rate {rate:g}", args.ssh_target, args.container), end="")
        if args.duration > 0:
            try:
                time.sleep(args.duration)
            finally:
                print(run_rcon(f"tick rate {args.restore_rate:g}", args.ssh_target, args.container), end="")
        return

    if args.command == "sprint":
        if args.value is None:
            raise SystemExit("sprint requires a duration value accepted by /tick sprint")
        print(run_rcon(f"tick sprint {args.value}", args.ssh_target, args.container), end="")


if __name__ == "__main__":
    main()
