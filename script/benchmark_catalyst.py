#!/usr/bin/env python3
"""Compare clean Release builds sequentially on the same isolated native runner."""
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time


def output(*command, cwd=None):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def main():
    baseline, candidate, evidence = (Path(arg).resolve() for arg in sys.argv[1:])
    if os.environ.get("CI") != "true":
        raise SystemExit("benchmark launch checks require an isolated CI desktop")
    evidence.mkdir(parents=True, exist_ok=True)
    result = {
        "machine": {"architecture": output("uname", "-m"),
                    "cpu": output("sysctl", "-n", "machdep.cpu.brand_string"),
                    "logical_cpus": int(output("sysctl", "-n", "hw.logicalcpu")),
                    "memory_bytes": int(output("sysctl", "-n", "hw.memsize")),
                    "macos": output("sw_vers", "-productVersion"),
                    "xcode": output("xcodebuild", "-version")},
        "builds": {},
        "method": "Same runner, baseline then candidate, separate empty DerivedData, no restored compiler cache. OS file cache may warm between runs.",
    }
    for label, root in (("baseline", baseline), ("candidate", candidate)):
        if (root / ".build").exists() or output("git", "status", "--porcelain", cwd=root):
            raise SystemExit(f"{label} must be a clean checkout without .build")
        destination = evidence / label
        destination.mkdir()
        source = output("git", "rev-parse", "HEAD", cwd=root)
        subprocess.run(["npm", "ci"], cwd=root, check=True)
        started = time.monotonic()
        with (destination / "build.log").open("w") as log:
            run = subprocess.run(["bash", "script/build_and_run.sh", "package"],
                                 cwd=root, stdout=log, stderr=subprocess.STDOUT)
        build = {"source": source, "package_seconds": round(time.monotonic() - started, 3),
                 "exit_code": run.returncode, "stages": []}
        result["builds"][label] = build
        for path in sorted((root / ".build/timings").glob("*.jsonl")):
            shutil.copy2(path, destination / path.name)
            build["stages"].extend(json.loads(line) for line in path.read_text().splitlines())
        (evidence / "comparison.json").write_text(json.dumps(result, indent=2) + "\n")
        run.check_returncode()
        app = root / "dist/魏碑.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        assert info["WeiBeiGitCommit"] == source and info["WeiBeiSourceDirty"] is False
        assert info["WeiBeiAcceptanceChecks"] is False and info["WeiBeiBuildConfiguration"] == "Release"
        assert info["WeiBeiArchitecture"] == result["machine"]["architecture"]
        subprocess.run(["python3", "script/verify_built_app.py", str(app), result["machine"]["architecture"]], cwd=root, check=True)
        subprocess.run(["bash", "script/verify_app_launch.sh", str(app)], cwd=root, check=True)
        shutil.copy2(app / "Contents/Info.plist", destination / "Info.plist")
        build["executable_bytes"] = (app / "Contents/MacOS/WeiBei").stat().st_size
        build["launch"] = "passed"
        text = (destination / "build.log").read_text()
        build["swift_compile_tasks"] = len(re.findall(r"^SwiftCompile normal .*\(in target", text, re.M))
        (evidence / "comparison.json").write_text(json.dumps(result, indent=2) + "\n")
        print(f"{label}: {json.dumps(build)}", flush=True)
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a") as out:
            out.write("| 同机冷构建 | 编译 | 完整 App 构建与校验 |\n|---|---:|---:|\n")
            for label, build in result["builds"].items():
                seconds = sum(s["seconds"] for s in build["stages"] if s["stage"].startswith("compile-"))
                out.write(f"| {label} | {seconds:.1f} s | {build['package_seconds']:.1f} s |\n")


if __name__ == "__main__":
    main()
