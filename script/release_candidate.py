#!/usr/bin/env python3
"""Validate an immutable release set and publish that exact set, including after a retry."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request
import xml.etree.ElementTree as ET

from build_number import validate as validate_build_number

REPOSITORY = "WroughtMind/weibei"


def gh(*arguments, data=None):
    return subprocess.check_output(["gh", *arguments], text=True,
                                   input=None if data is None else json.dumps(data)).strip()


def optional_api(path):
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if result.returncode == 0:
        return json.loads(result.stdout)
    if "HTTP 404" in result.stderr:
        return None
    raise RuntimeError(result.stderr)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def public_files(version):
    return {f"WeiBei-{version}-macOS-{arch}.dmg{suffix}"
            for arch in ("arm64", "x86_64") for suffix in ("", ".sha256")} | {
        "appcast-arm64.xml", "appcast-x86_64.xml", "appcast.xml", "weibei.rb",
        f"WeiBei-{version}-debug-symbols.zip"}


def verify(root, version, source, run_id=None):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[0-9a-f]{40}", source):
        raise ValueError("invalid version or source identity")
    record = json.loads((root / "candidate.json").read_text())
    if record["version"] != version or record["source_revision"] != source:
        raise ValueError("candidate version/source differs from requested release")
    validate_build_number(record["build_number"])
    if run_id is not None and str(record["workflow_run"]) != str(run_id):
        raise ValueError("candidate belongs to another workflow run")
    if record["architectures"] != ["arm64", "x86_64"]:
        raise ValueError("candidate must contain both native architectures")
    expected = public_files(version) | {"release-notes.md", "package-arm64.json", "package-x86_64.json",
                                        "update-verification-arm64.json", "update-verification-x86_64.json"}
    if set(record["files"]) != expected:
        raise ValueError("candidate asset set is incomplete or unexpected")
    for name, checksum in record["files"].items():
        path = root / name
        if Path(name).name != name or path.is_symlink() or not path.is_file():
            raise ValueError(f"invalid candidate file: {name}")
        if digest(path) != checksum:
            raise ValueError(f"candidate hash mismatch: {name}")
    sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    for arch in record["architectures"]:
        dmg = root / f"WeiBei-{version}-macOS-{arch}.dmg"
        checksum = record["files"][dmg.name]
        if (root / (dmg.name + ".sha256")).read_text().split() != [checksum, dmg.name]:
            raise ValueError(f"checksum receipt mismatch: {arch}")
        package = json.loads((root / f"package-{arch}.json").read_text())
        if (package["source_revision"] != source or package["source_dirty"] is not False or
                package["architecture"] != arch or package["download_file"] != dmg.name or
                package["download_bytes"] != dmg.stat().st_size):
            raise ValueError(f"package provenance mismatch: {arch}")
        update = json.loads((root / f"update-verification-{arch}.json").read_text())
        flags = ("passed", "actual_sparkle_installation_passed", "production_dmg_signature_verified",
                 "production_feed_signature_verified", "modified_dmg_rejected", "modified_feed_rejected",
                 "installed_codesign_verified")
        if (not all(update.get(flag) is True for flag in flags) or update["source_revision"] != source or
                update["build_number"] != record["build_number"] or update["dmg_sha256"] != checksum):
            raise ValueError(f"update installation/signature evidence mismatch: {arch}")
        item = ET.parse(root / f"appcast-{arch}.xml").find("./channel/item")
        enclosure = item.find("enclosure")
        if (enclosure.get("url") != f"https://github.com/{REPOSITORY}/releases/download/v{version}/{dmg.name}" or
                int(enclosure.get("length")) != dmg.stat().st_size or
                (item.findtext(sparkle + "version") or enclosure.get(sparkle + "version")) != record["build_number"] or
                (item.findtext(sparkle + "shortVersionString") or enclosure.get(sparkle + "shortVersionString")) != version):
            raise ValueError(f"update feed identity mismatch: {arch}")
    if (root / "appcast.xml").read_bytes() != (root / "appcast-arm64.xml").read_bytes():
        raise ValueError("legacy ARM feed differs")
    return record


def verify_run(run_id, source):
    if not str(run_id).isdigit():
        raise ValueError("candidate run must be numeric")
    run = json.loads(gh("api", f"repos/{REPOSITORY}/actions/runs/{run_id}"))
    if (run["head_sha"] != source or run["event"] != "workflow_dispatch" or
            run["path"].split("@")[0] != ".github/workflows/release.yml"):
        raise ValueError("candidate must come from the release workflow at the exact source")
    jobs = json.loads(gh("api", f"repos/{REPOSITORY}/actions/runs/{run_id}/jobs?per_page=100"))["jobs"]
    if not any(job["name"] == "汇总并验证完整候选资产" and job["conclusion"] == "success" for job in jobs):
        raise ValueError("candidate preparation did not succeed")


def publish(root, record):
    version, source = record["version"], record["source_revision"]
    tag = "v" + version
    tag_commit = optional_api(f"repos/{REPOSITORY}/commits/{tag}")
    if tag_commit is not None and tag_commit["sha"] != source:
        raise ValueError("existing tag points at another commit")
    latest = optional_api(f"repos/{REPOSITORY}/releases/latest")
    if latest and latest["tag_name"] != tag:
        previous_version = latest["tag_name"].removeprefix("v")
        if not re.fullmatch(r"\d+\.\d+\.\d+", previous_version) or tuple(map(int, previous_version.split("."))) >= tuple(map(int, version.split("."))):
            raise ValueError("candidate would regress the latest public version")
        for arch in ("arm64", "x86_64"):
            url = f"https://github.com/{REPOSITORY}/releases/download/{latest['tag_name']}/appcast-{arch}.xml"
            with urllib.request.urlopen(url, timeout=60) as response:
                feed = ET.parse(response)
            key = "{http://www.andymatuschak.org/xml-namespaces/sparkle}version"
            item = feed.find("./channel/item")
            previous_build = item.findtext(key) or item.find("enclosure").get(key)
            if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", previous_build or "") or tuple(map(int, record["build_number"].split("."))) <= tuple(map(int, previous_build.split("."))):
                raise ValueError("candidate build is no newer than the delivered update")
    release = optional_api(f"repos/{REPOSITORY}/releases/tags/{tag}")
    if release is None:
        gh("release", "create", tag, "--repo", REPOSITORY, "--target", source, "--draft",
           "--notes-file", str(root / "release-notes.md"), "--title", "魏碑 " + version)
    else:
        if release["target_commitish"] != source:
            raise ValueError("existing release points at another source; refusing to replace it")
        if not release["draft"]:
            # Public releases are immutable. The caller verifies public bytes again.
            if release.get("prerelease") or set(a["name"] for a in release["assets"]) != public_files(version):
                raise ValueError("existing public release differs from candidate")
            for asset in release["assets"]:
                if asset.get("digest") != "sha256:" + record["files"][asset["name"]]:
                    raise ValueError("existing public asset differs from candidate")
            return
    gh("release", "upload", tag, "--repo", REPOSITORY, "--clobber",
       *[str(root / name) for name in sorted(public_files(version))])
    gh("release", "edit", tag, "--repo", REPOSITORY, "--notes-file", str(root / "release-notes.md"),
       "--latest", "--draft=false")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--run-id")
    parser.add_argument("--verify-run", action="store_true")
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()
    if args.verify_run:
        verify_run(args.run_id, args.source)
    record = verify(args.root, args.version, args.source, args.run_id)
    if args.publish:
        publish(args.root, record)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write(f"build_number={record['build_number']}\n")
    print(f"candidate verified: {record['source_revision']} / {record['build_number']}")


if __name__ == "__main__":
    main()
