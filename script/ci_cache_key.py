#!/usr/bin/env python3
"""Cache identity excludes release numbers but includes toolchains and package patches."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from ci_metadata import without_version


def main():
    architecture = sys.argv[1]
    if architecture not in ("arm64", "x86_64"):
        raise SystemExit("unsupported cache architecture")
    digest = hashlib.sha256()
    for command in (["sw_vers", "-productVersion"], ["xcodebuild", "-version"],
                    ["xcrun", "--sdk", "macosx", "--show-sdk-version"]):
        digest.update(subprocess.check_output(command))
    for name in ("package.json", "package-lock.json"):
        value = without_version(json.loads(Path(name).read_text()), name.endswith("-lock.json"))
        digest.update(json.dumps(value, sort_keys=True).encode())
    paths = [Path("Package.resolved"), Path("Package.swift"), Path("App/project.yml"),
             Path("App/WeiBei.xcodeproj/project.pbxproj"), Path("script/build_and_run.sh")]
    paths += sorted(Path("App/script").glob("*.patch"))
    for path in paths:
        digest.update(str(path).encode())
        digest.update(path.read_bytes())
    print(f"prefix=weibei-catalyst-v1-{architecture}-{digest.hexdigest()}-")


if __name__ == "__main__":
    main()
