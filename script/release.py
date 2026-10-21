#!/usr/bin/env python3
"""Continue an authorized, reviewed release from PR checks through public channels."""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import time
import urllib.request
import uuid

from release_candidate import REPOSITORY, gh, verify, verify_run
from verify_public_release import verify_public

TAP = "taekchef/homebrew-tap"
SITE = "https://wroughtmind.github.io/weibei/"


def now():
    return datetime.now(timezone.utc).isoformat()


def pr_ready(pr, reviewed_head):
    if pr["headRefOid"] != reviewed_head or pr["baseRefName"] != "main":
        raise ValueError("PR head/base changed after review")
    if pr["isDraft"] or pr["reviewDecision"] == "CHANGES_REQUESTED":
        raise ValueError("PR has unfinished review")
    if pr["state"] not in ("OPEN", "MERGED"):
        raise ValueError("PR was closed without merge")
    checks = pr["statusCheckRollup"]
    if not checks:
        return False
    for check in checks:
        if check.get("conclusion") in ("FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE") or check.get("state") in ("ERROR", "FAILURE"):
            raise ValueError("PR has a failed or cancelled check")
    finished = all(c.get("status", "COMPLETED") == "COMPLETED" and c.get("state") != "PENDING" for c in checks)
    if pr["mergeStateStatus"] in ("DIRTY", "BEHIND") or (finished and pr["mergeStateStatus"] == "BLOCKED"):
        raise ValueError("PR requires conflict resolution, a main update or a repository approval")
    return (pr["mergeStateStatus"] == "CLEAN" and
            all(c.get("status", "COMPLETED") == "COMPLETED" and
                c.get("conclusion", c.get("state")) in ("SUCCESS", "SKIPPED", "NEUTRAL") for c in checks) and
            any(c.get("name") == "快速编译与核心自检" and c.get("conclusion") == "SUCCESS" for c in checks))


def read_pr(number):
    return json.loads(gh("pr", "view", str(number), "--repo", REPOSITORY, "--json",
                         "number,state,headRefOid,baseRefName,mergeStateStatus,isDraft,reviewDecision,statusCheckRollup,mergedAt,mergeCommit"))


def wait_run(repository, run_id):
    subprocess.run(["gh", "run", "watch", str(run_id), "--repo", repository,
                    "--exit-status", "--interval", "30"], check=True)
    run = json.loads(gh("api", f"repos/{repository}/actions/runs/{run_id}"))
    if run["conclusion"] != "success":
        raise ValueError("workflow has not succeeded")
    return run


def matching_runs(repository, workflow, **filters):
    arguments = ["run", "list", "--repo", repository, "--workflow", workflow,
                 "--json", "databaseId,headSha,displayTitle,status,conclusion,event", "--limit", "100"]
    for key, value in filters.items():
        arguments += ["--" + key, value]
    return json.loads(gh(*arguments))


def sync_tap(root, record, stop):
    path = f"repos/{TAP}/contents/Casks/weibei.rb"
    current = json.loads(gh("api", path))
    content = (root / "weibei.rb").read_bytes()
    previous = base64.b64decode(current["content"])
    old_version = re.search(rb'\bversion\s+"(\d+\.\d+\.\d+)"', previous)
    if not old_version or tuple(map(int, old_version[1].split(b"."))) > tuple(map(int, record["version"].split("."))):
        raise ValueError("Tap version is newer or unrecognized; refusing to replace it")
    if previous != content:
        result = json.loads(gh("api", "--method", "PUT", path, "--input", "-", data={
            "message": "更新魏碑 " + record["version"], "sha": current["sha"],
            "content": base64.b64encode(content).decode()}))
        commit = result["commit"]["sha"]
    else:
        commit = json.loads(gh("api", f"repos/{TAP}/commits?path=Casks/weibei.rb&per_page=1"))[0]["sha"]
    while not stop.is_set():
        runs = matching_runs(TAP, "install.yml", commit=commit)
        if runs:
            run_id = runs[0]["databaseId"]
            break
        stop.wait(10)
    else:
        raise RuntimeError("channel verification cancelled after another failure")
    wait_run(TAP, run_id)
    destination = Path(tempfile.mkdtemp(prefix="homebrew-installation-", dir=root.parent))
    gh("run", "download", str(run_id), "--repo", TAP, "--dir", str(destination))
    for arch in ("arm64", "x86_64"):
        receipt = json.loads((destination / f"install-{arch}/install-verification.json").read_text())
        if (receipt.get("passed") is not True or receipt["architecture"] != arch or
                receipt["version"] != record["version"] or receipt["source_revision"] != record["source_revision"] or
                receipt["build_number"] != record["build_number"] or receipt.get("strict_codesign_verified") is not True):
            raise ValueError(f"Homebrew installed a different/unverified App: {arch}")
    return {"commit": commit, "run": run_id, "architectures": ["arm64", "x86_64"]}


def verify_website(record, stop):
    # The site deploys on release workflow completion; wait for its public result.
    while not stop.is_set():
        request = urllib.request.Request(SITE + "release.json?version=" + record["version"],
                                         headers={"Cache-Control": "no-cache", "User-Agent": "WeiBei-release-verification"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = json.load(response)
        if data.get("version") == "v" + record["version"] and data.get("available") is True:
            expected = {f"WeiBei-{record['version']}-macOS-{arch}.dmg" for arch in ("arm64", "x86_64")}
            if {asset["name"] for asset in data["assets"]} != expected:
                raise ValueError("website architecture downloads are incomplete")
            for asset in data["assets"]:
                if asset["download_url"] != f"https://github.com/{REPOSITORY}/releases/download/v{record['version']}/{asset['name']}":
                    raise ValueError("website points at another release")
            return data
        runs = matching_runs(REPOSITORY, "pages.yml", branch="main")
        if runs and runs[0]["status"] == "completed" and runs[0]["conclusion"] not in ("success", "cancelled"):
            raise ValueError("website deployment failed")
        latest = json.loads(gh("api", f"repos/{REPOSITORY}/releases/latest"))
        if latest["tag_name"] != "v" + record["version"]:
            raise ValueError("another release became latest before website verification")
        stop.wait(30)
    raise RuntimeError("channel verification cancelled after another failure")


def verify_version_at_source(source, version):
    def content(path):
        item = json.loads(gh("api", f"repos/{REPOSITORY}/contents/{path}?ref={source}"))
        return base64.b64decode(item["content"])
    package = json.loads(content("package.json"))
    lock = json.loads(content("package-lock.json"))
    if not (content("VERSION").decode().strip() == package["version"] == lock["version"] ==
            lock["packages"][""]["version"] == version):
        raise ValueError("requested version differs from reviewed manifests")
    for path in (f"Docs/releases/v{version}.md", f"Docs/update-summaries/v{version}.md"):
        if not content(path).strip():
            raise ValueError("release notes/update summary is empty")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--reviewed-head", required=True, help="exact commit whose code and necessary UX evidence were reviewed")
    parser.add_argument("--version", required=True)
    parser.add_argument("--publish", action="store_true", help="explicit authorization to merge, publish and sync distribution channels")
    parser.add_argument("--candidate-run", help="reuse a verified release candidate at the merged source")
    args = parser.parse_args()
    if not args.publish:
        parser.error("this command changes public state; --publish is required after release authorization")
    if not re.fullmatch(r"[0-9a-f]{40}", args.reviewed_head) or not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("invalid reviewed commit/version")
    if args.candidate_run and not args.candidate_run.isdigit():
        parser.error("candidate run must be numeric")
    root = Path(__file__).resolve().parent.parent / "dist" / f"release-flow-{args.pr}"
    root.mkdir(parents=True, exist_ok=True)
    state_file = root / "state.json"
    identity = {"pr": args.pr, "reviewed_head": args.reviewed_head, "version": args.version}
    state = json.loads(state_file.read_text()) if state_file.exists() else {
        **identity, "request_id": str(uuid.uuid4()), "started_at": now(), "events": []}
    if any(state.get(key) != value for key, value in identity.items()):
        raise ValueError("saved release belongs to another reviewed request")

    def save(stage, **values):
        state.update(values)
        state["events"].append({"stage": stage, "at": now()})
        temporary = state_file.with_suffix(".tmp")
        temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
        temporary.replace(state_file)
        print(stage, flush=True)

    save("release authorization recorded", review_acknowledged_at=state.get("review_acknowledged_at", now()))
    pr = read_pr(args.pr)
    if pr["headRefOid"] != args.reviewed_head or pr["baseRefName"] != "main":
        raise ValueError("PR changed since review")
    verify_version_at_source(args.reviewed_head, args.version)
    if pr["state"] != "MERGED":
        if pr["state"] != "OPEN":
            raise ValueError("PR is not open")
        while not pr_ready(pr, args.reviewed_head):
            if pr["state"] == "MERGED":
                break
            time.sleep(30)
            pr = read_pr(args.pr)
        completed = [check["completedAt"] for check in pr["statusCheckRollup"] if check.get("completedAt")]
        save("required checks and supplied review complete", ready_at=now(),
             ci_completed_at=max(completed) if completed else None)
        if pr["state"] != "MERGED":
            gh("pr", "merge", str(args.pr), "--repo", REPOSITORY, "--merge", "--match-head-commit", args.reviewed_head)
        pr = read_pr(args.pr)
    source = pr["mergeCommit"]["oid"]
    save("merged", source_revision=source, merged_at=pr["mergedAt"])
    if args.candidate_run and args.candidate_run != state.get("candidate_run"):
        verify_run(args.candidate_run, source)
        save("resume from verified candidate", candidate_run=args.candidate_run, request_id=str(uuid.uuid4()))
    title = "release-request-" + state["request_id"]
    runs = [run for run in matching_runs(REPOSITORY, "release.yml", commit=source, event="workflow_dispatch")
            if title in run["displayTitle"]]
    if not runs:
        main_source = json.loads(gh("api", f"repos/{REPOSITORY}/commits/main"))["sha"]
        if main_source != source:
            raise ValueError("main advanced after the reviewed merge; prepare a newly reviewed release")
        command = ["workflow", "run", "release.yml", "--repo", REPOSITORY, "--ref", "main",
                   "-f", "version=" + args.version, "-f", "publish=true", "-f", "expected_source=" + source,
                   "-f", "request_id=" + state["request_id"]]
        if state.get("candidate_run"):
            command += ["-f", "candidate_run=" + state["candidate_run"]]
        gh(*command)
        while not runs:
            time.sleep(5)
            runs = [run for run in matching_runs(REPOSITORY, "release.yml", commit=source, event="workflow_dispatch")
                    if title in run["displayTitle"]]
    run_id = runs[0]["databaseId"]
    save("release workflow selected", workflow_run=run_id)
    run = wait_run(REPOSITORY, run_id)
    candidate = Path(tempfile.mkdtemp(prefix=f"candidate-{run_id}-", dir=root))
    gh("run", "download", str(run_id), "--repo", REPOSITORY, "--name", "release-ready", "--dir", str(candidate))
    record = verify(candidate, args.version, source)
    verify_run(record["workflow_run"], source)
    jobs = json.loads(gh("api", f"repos/{REPOSITORY}/actions/runs/{run_id}/jobs?per_page=100"))["jobs"]
    prepared = next(job["completed_at"] for job in jobs if job["name"] == "汇总并验证完整候选资产")
    save("public release workflow succeeded", build_number=record["build_number"],
         workflow_started_at=run["created_at"], candidate_completed_at=prepared)
    stop = threading.Event()
    with ThreadPoolExecutor() as executor:
        futures = {executor.submit(verify_public, candidate, record): "public",
                   executor.submit(sync_tap, candidate, record, stop): "homebrew",
                   executor.submit(verify_website, record, stop): "website"}
        try:
            for future in as_completed(futures):
                name = futures[future]
                receipt = future.result()
                (root / f"{name}.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
                save(name + " verified", **({"published_at": receipt["published_at"]} if name == "public" else {}))
        finally:
            stop.set()
    save("release and distribution complete", completed_at=now())
    print("receipts: " + str(root))


if __name__ == "__main__":
    main()
