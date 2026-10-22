#!/usr/bin/env python3
"""Verify actual acceptance-to-production builds reused unchanged Swift targets."""
from pathlib import Path
import re
import sys


def verify(acceptance, production):
    caches = [set(re.findall(r"/[^\s]+\.sdkstatcache", text))
              for text in (acceptance, production)]
    assert caches[0] and caches[0] == caches[1], f"SDK cache identity changed: {caches}"
    targets = set(re.findall(r"^SwiftCompile normal .*\(in target '([^']+)'", production, re.M))
    expected = {"WeiBei", "WeiBeiWindowBridge"}
    assert targets == expected, f"Production rebuilt unexpected Swift targets: {sorted(targets)}"
    print("正式包只重编主应用和窗口组件；SDK 缓存身份保持一致。")


if __name__ == "__main__":
    verify(*(Path(path).read_text() for path in sys.argv[1:]))
