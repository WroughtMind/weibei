#!/usr/bin/env python3
"""Run the Swift self-check and PDF workers without registering Dock applications."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, help="Use already-built self-check and worker binaries")
    args, check_args = parser.parse_known_args()
    binary_dir = args.bin_dir
    if binary_dir is None:
        for product in ("WeiBeiSelfCheck", "WeiBeiPDFTextWorker"):
            subprocess.run(["swift", "build", "--product", product], cwd=ROOT, check=True)
        binary_dir = Path(subprocess.check_output(
            ["swift", "build", "--show-bin-path"], cwd=ROOT, text=True
        ).strip())
    binary_dir = binary_dir.resolve()

    # Launch Services uses the enclosing app's identity before AppKit can set
    # an activation policy. A real background bundle prevents the initial Dock
    # launch notification for both the self-check and its PDF subprocesses.
    with tempfile.TemporaryDirectory(prefix="weibei-self-check-") as directory:
        contents = Path(directory) / "WeiBeiSelfCheck.app" / "Contents"
        for name in ("MacOS", "Helpers", "Resources"):
            (contents / name).mkdir(parents=True, exist_ok=True)
        executable = contents / "MacOS" / "WeiBeiSelfCheck"
        shutil.copy2(binary_dir / "WeiBeiSelfCheck", executable)
        shutil.copy2(binary_dir / "WeiBeiPDFTextWorker", contents / "Helpers" / "WeiBeiPDFTextWorker")
        for resource in binary_dir.glob("*.bundle"):
            shutil.copytree(resource, contents / "Resources" / resource.name)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.changfenhuang.weibei.SelfCheck",
            "CFBundleName": "WeiBeiSelfCheck",
            "CFBundleExecutable": "WeiBeiSelfCheck",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "LSBackgroundOnly": True,
        }))
        return subprocess.run([str(executable), *check_args], cwd=ROOT).returncode


if __name__ == "__main__":
    raise SystemExit(main())
