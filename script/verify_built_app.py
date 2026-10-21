#!/usr/bin/env python3
"""Reject stale, diagnostic or differently configured Apps before DMG assembly."""
from pathlib import Path
import plistlib
import subprocess
import sys

from build_number import validate


def verify(info, architecture, version, build_number, source, public_key):
    expected = {
        "CFBundleIdentifier": "com.changfenhuang.weibei",
        "CFBundleShortVersionString": version, "CFBundleVersion": build_number,
        "WeiBeiGitCommit": source, "WeiBeiArchitecture": architecture,
        "WeiBeiBuildConfiguration": "Release",
        "WeiBeiSourceDirty": False, "WeiBeiAcceptanceChecks": False,
        "SUPublicEDKey": public_key,
        "SUFeedURL": f"https://github.com/WroughtMind/weibei/releases/latest/download/appcast-{architecture}.xml",
    }
    for key, value in expected.items():
        if type(info.get(key)) is not type(value) or info.get(key) != value:
            raise ValueError(f"built App does not match current release input: {key}")


def main():
    import os
    import re
    root = Path(__file__).resolve().parent.parent
    app, architecture = Path(sys.argv[1]), sys.argv[2]
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    default_key = re.search(r'SPARKLE_PUBLIC_KEY="\$\{WEIBEI_SPARKLE_PUBLIC_KEY:-([^}]+)\}"',
                            (root / "script/build_and_run.sh").read_text()).group(1)
    verify(info, architecture, (root / "VERSION").read_text().strip(),
           validate(os.environ.get("WEIBEI_BUILD_NUMBER") or info.get("CFBundleVersion", "")),
           subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
           os.environ.get("WEIBEI_SPARKLE_PUBLIC_KEY") or default_key)
    print("prebuilt production App matches source, architecture, version, build and update identity")


if __name__ == "__main__":
    main()
