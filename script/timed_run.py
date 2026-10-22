#!/usr/bin/env python3
"""Run a build stage, stream its log and retain timings even when it fails."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--record", type=Path, required=True)
    parser.add_argument("--log", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("a command is required")
    started = datetime.now(timezone.utc).isoformat()
    start = time.monotonic()
    print(f"stage started: {args.name}", flush=True)
    log = None
    code = 1
    try:
        if args.log:
            args.log.parent.mkdir(parents=True, exist_ok=True)
            log = args.log.open("w")
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, errors="replace", bufsize=1) as process:
            for line in process.stdout:
                print(line, end="", flush=True)
                if log:
                    log.write(line)
                    log.flush()
            code = process.wait()
    finally:
        if log:
            log.close()
        seconds = round(time.monotonic() - start, 3)
        args.record.parent.mkdir(parents=True, exist_ok=True)
        with args.record.open("a") as output:
            output.write(json.dumps({"stage": args.name, "started_at": started,
                                     "seconds": seconds, "exit_code": code}) + "\n")
        print(f"stage finished: {args.name}; seconds={seconds}; exit={code}", flush=True)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
