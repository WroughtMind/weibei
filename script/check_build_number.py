#!/usr/bin/env python3
"""Protect timestamp validation, batch reuse and upgrade ordering."""
from pathlib import Path
import os
import sys
sys.dont_write_bytecode = True
import subprocess
from build_number import validate

assert validate("20260909.1530.27") == "20260909.1530.27"
assert validate("20240229.2359.59") == "20240229.2359.59"
for value in ["1806", "20260909.1530", "20260229.1200.00", "20260909.2460.00", "20260909.1530.27\n", ""]:
    try:
        validate(value)
    except ValueError:
        pass
    else:
        raise AssertionError(value)
script = str(Path(__file__).with_name("build_number.py"))
env = {**os.environ, "WEIBEI_BUILD_NUMBER": "20260909.1530.27"}
for previous, succeeds in [("1806", True), ("20260909.1530.26", True), ("20260909.1530.27", False), ("20260910.0000.00", False)]:
    result = subprocess.run(["python3", script, "--after", previous], env=env, capture_output=True, text=True)
    assert (result.returncode == 0) == succeeds
    if succeeds:
        assert result.stdout.strip() == env["WEIBEI_BUILD_NUMBER"]
print("build number checks passed")

import tempfile
with tempfile.TemporaryDirectory() as directory:
    feed = Path(directory) / "appcast.xml"
    for version, succeeds in [("1806", True), ("20260910.0000.00", False), ("bad", False)]:
        feed.write_text(f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure sparkle:version="{version}"/></item></channel></rss>')
        result = subprocess.run(["python3", script, "--after-feed", str(feed)], env=env, capture_output=True)
        assert (result.returncode == 0) == succeeds
