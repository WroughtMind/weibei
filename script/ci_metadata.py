#!/usr/bin/env python3
"""Compare manifest contents, not file names, when routing a version-only change."""
import copy
import json
import re
import subprocess
import sys


def without_version(document, lock=False):
    value = copy.deepcopy(document)
    if not re.fullmatch(r"\d+\.\d+\.\d+", value.pop("version", "")):
        raise ValueError("missing numeric root version")
    if lock:
        root = value["packages"][""]
        if not re.fullmatch(r"\d+\.\d+\.\d+", root.pop("version", "")):
            raise ValueError("missing lockfile root version")
    return value


def version_only(base, head, path):
    if path not in ("package.json", "package-lock.json"):
        return False
    try:
        documents = [json.loads(subprocess.check_output(
            ["git", "show", f"{ref}:{path}"], stderr=subprocess.DEVNULL)) for ref in (base, head)]
        return documents[0] != documents[1] and (
            without_version(documents[0], path.endswith("-lock.json")) ==
            without_version(documents[1], path.endswith("-lock.json")))
    except (ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        return False


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: ci_metadata.py BASE HEAD package.json|package-lock.json")
    raise SystemExit(0 if version_only(*sys.argv[1:]) else 1)
