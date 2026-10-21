#!/usr/bin/env python3
"""Check downloaded public bytes against the exact verified candidate."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import urllib.request

from release_candidate import REPOSITORY, gh, public_files, verify


def download_receipt(url):
    request = urllib.request.Request(url, headers={"User-Agent": "WeiBei-release-verification"})
    with urllib.request.urlopen(request, timeout=120) as response:
        digest, size = hashlib.sha256(), 0
        for block in iter(lambda: response.read(1024 * 1024), b""):
            digest.update(block)
            size += len(block)
        return {"sha256": digest.hexdigest(), "bytes": size,
                "resolved_url": response.url.split("?")[0]}


def verify_public(root, record):
    version = record["version"]
    release = json.loads(gh("api", f"repos/{REPOSITORY}/releases/tags/v{version}"))
    latest = json.loads(gh("api", f"repos/{REPOSITORY}/releases/latest"))
    tag = json.loads(gh("api", f"repos/{REPOSITORY}/commits/v{version}"))
    if (release["draft"] or release["prerelease"] or release["id"] != latest["id"] or
            release["target_commitish"] != record["source_revision"] or tag["sha"] != record["source_revision"] or
            release["body"].strip() != (root / "release-notes.md").read_text().strip()):
        raise ValueError("public release identity/notes/latest does not match candidate")
    assets = {asset["name"]: asset for asset in release["assets"]}
    if set(assets) != public_files(version):
        raise ValueError("public asset set differs from candidate")

    def asset_receipt(name):
        asset = assets[name]
        expected_url = f"https://github.com/{REPOSITORY}/releases/download/v{version}/{name}"
        if asset["state"] != "uploaded" or asset["browser_download_url"] != expected_url:
            raise ValueError(f"unexpected public asset URL/state: {name}")
        observed = download_receipt(expected_url)
        if (observed["sha256"] != record["files"][name] or
                observed["bytes"] != asset["size"] or observed["bytes"] != (root / name).stat().st_size):
            raise ValueError(f"public bytes differ from candidate: {name}")
        return name, observed

    with ThreadPoolExecutor() as executor:
        receipts = dict(executor.map(asset_receipt, sorted(assets)))
    feeds = {}
    for name in ("appcast-arm64.xml", "appcast-x86_64.xml", "appcast.xml"):
        observed = download_receipt(f"https://github.com/{REPOSITORY}/releases/latest/download/{name}")
        if observed["sha256"] != record["files"][name]:
            raise ValueError(f"latest feed differs: {name}")
        feeds[name] = observed
    return {"version": version, "source_revision": record["source_revision"],
            "published_at": release["published_at"],
            "public_assets": receipts, "latest_feeds": feeds}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    record = verify(args.root, args.version, args.source)
    receipt = verify_public(args.root, record)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    print("public assets and latest feeds match the verified candidate")


if __name__ == "__main__":
    main()
