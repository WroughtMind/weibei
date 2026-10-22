#!/usr/bin/env python3
"""Run the Swift self-check and PDF workers without registering Dock applications."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def exit_on_signal(signum, _frame):
    raise SystemExit(128 + signum)


def run(command, *, capture_output=False):
    process = None
    interrupted = None

    def forward_signal(signum, _frame):
        nonlocal interrupted
        interrupted = signum
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signum)
            except ProcessLookupError:
                pass

    previous = {sig: signal.signal(sig, forward_signal)
                for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        # A separate group lets cancellation also reach PDF worker descendants.
        with subprocess.Popen(command, cwd=ROOT, start_new_session=True,
                              stdout=subprocess.PIPE if capture_output else None,
                              text=True) as process:
            if interrupted is not None:
                forward_signal(interrupted, None)
            output, _ = process.communicate()
            code = process.returncode
        if interrupted is not None:
            raise SystemExit(128 + interrupted)
        if code:
            raise SystemExit(code if code > 0 else 128 - code)
        return output
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, help="Use already-built self-check and worker binaries")
    args, check_args = parser.parse_known_args()
    binary_dir = args.bin_dir
    if binary_dir is None:
        for product in ("WeiBeiSelfCheck", "WeiBeiPDFTextWorker"):
            run(["swift", "build", "--product", product])
        binary_dir = Path(run(
            ["swift", "build", "--show-bin-path"], capture_output=True
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
        run([str(executable), *check_args])
    return 0


if __name__ == "__main__":
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, exit_on_signal)
    raise SystemExit(main())
