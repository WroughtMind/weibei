"""Release routing, artifact identity and retry boundaries; no public mutations."""
import base64
import copy
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import ci_metadata
import release
import release_candidate as candidate
import verify_built_app
import verify_public_release

ROOT = Path(__file__).resolve().parent.parent
SOURCE = "a" * 40
VERSION = "0.0.3"
BUILD = "20261021.1200.00"


class ManifestRouting(unittest.TestCase):
    def test_real_git_version_only_and_dependency_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args], text=True).strip()
            def commit():
                git("add", ".")
                git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "test")
                return git("rev-parse", "HEAD")
            def scopes(base, head):
                output = subprocess.check_output(["bash", str(ROOT / "script/ci_changed_scopes.sh"), base, head], cwd=root, text=True)
                return {key for key, value in (line.split("=") for line in output.splitlines()) if value == "true"}
            git("init", "-q")
            package = {"name": "test", "version": "0.0.2", "scripts": {"build": "node build.js"}, "dependencies": {"example": "1.0.0"}}
            lock = {"version": "0.0.2", "packages": {"": {"version": "0.0.2"}, "node_modules/example": {"version": "1.0.0"}}}
            def write():
                (root / "package.json").write_text(json.dumps(package))
                (root / "package-lock.json").write_text(json.dumps(lock))
            write()
            before = commit()
            package["version"] = lock["version"] = lock["packages"][""]["version"] = VERSION
            write()
            version_commit = commit()
            self.assertEqual(scopes(before, version_commit), {"release"})
            for mutation in (lambda: package["dependencies"].update(example="2.0.0"),
                             lambda: package["scripts"].update(build="node other.js"),
                             lambda: lock["packages"]["node_modules/example"].update(version="2.0.0")):
                before = git("rev-parse", "HEAD")
                mutation()
                write()
                after = commit()
                self.assertEqual(scopes(before, after), {"code", "agent", "editor", "release", "tools"})
            before = git("rev-parse", "HEAD")
            (root / "package.json").write_text("invalid json")
            self.assertIn("code", scopes(before, commit()))
            before = git("rev-parse", "HEAD")
            (root / "package-lock.json").unlink()
            self.assertIn("code", scopes(before, commit()))

    def test_cache_manifest_identity_excludes_only_release_version(self):
        package = {"version": "0.0.2", "dependencies": {"x": "1.0.0"}}
        newer = {**package, "version": VERSION}
        self.assertEqual(ci_metadata.without_version(package), ci_metadata.without_version(newer))
        newer["dependencies"] = {"x": "2.0.0"}
        self.assertNotEqual(ci_metadata.without_version(package), ci_metadata.without_version(newer))


class PrebuiltApp(unittest.TestCase):
    def test_reject_wrong_source_architecture_configuration_and_update_identity(self):
        info = {"CFBundleIdentifier": "com.changfenhuang.weibei", "CFBundleShortVersionString": VERSION,
                "CFBundleVersion": BUILD, "WeiBeiGitCommit": SOURCE, "WeiBeiArchitecture": "arm64", "WeiBeiBuildConfiguration": "Release",
                "WeiBeiSourceDirty": False, "WeiBeiAcceptanceChecks": False, "SUPublicEDKey": "public-key",
                "SUFeedURL": "https://github.com/WroughtMind/weibei/releases/latest/download/appcast-arm64.xml"}
        verify_built_app.verify(info, "arm64", VERSION, BUILD, SOURCE, "public-key")
        for key, value in {"CFBundleIdentifier": "com.test.acceptance", "CFBundleShortVersionString": "0.0.2",
                           "CFBundleVersion": "20261020.1200.00", "WeiBeiGitCommit": "b" * 40,
                           "WeiBeiArchitecture": "x86_64", "WeiBeiSourceDirty": True,
                           "WeiBeiAcceptanceChecks": True, "WeiBeiBuildConfiguration": "Debug", "SUPublicEDKey": "wrong", "SUFeedURL": "wrong"}.items():
            with self.subTest(key=key), self.assertRaises(ValueError):
                verify_built_app.verify({**info, key: value}, "arm64", VERSION, BUILD, SOURCE, "public-key")
        with self.assertRaises(ValueError):
            verify_built_app.verify({**info, "WeiBeiSourceDirty": "false"}, "arm64", VERSION, BUILD, SOURCE, "public-key")


def make_candidate(root):
    record = {"version": VERSION, "source_revision": SOURCE, "build_number": BUILD,
              "workflow_run": "123", "architectures": ["arm64", "x86_64"]}
    for arch in record["architectures"]:
        dmg = root / f"WeiBei-{VERSION}-macOS-{arch}.dmg"
        dmg.write_bytes(b"unit-test artifact " + arch.encode())
        checksum = candidate.digest(dmg)
        (root / (dmg.name + ".sha256")).write_text(checksum + "  " + dmg.name + "\n")
        (root / f"package-{arch}.json").write_text(json.dumps({"source_revision": SOURCE, "source_dirty": False,
            "architecture": arch, "download_file": dmg.name, "download_bytes": dmg.stat().st_size}))
        update = dict.fromkeys(("passed", "actual_sparkle_installation_passed", "production_dmg_signature_verified",
            "production_feed_signature_verified", "modified_dmg_rejected", "modified_feed_rejected", "installed_codesign_verified"), True)
        update.update(source_revision=SOURCE, build_number=BUILD, dmg_sha256=checksum)
        (root / f"update-verification-{arch}.json").write_text(json.dumps(update))
        (root / f"appcast-{arch}.xml").write_text(f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>{BUILD}</sparkle:version><sparkle:shortVersionString>{VERSION}</sparkle:shortVersionString>
        <enclosure url="https://github.com/WroughtMind/weibei/releases/download/v{VERSION}/{dmg.name}" length="{dmg.stat().st_size}"/>
        </item></channel></rss>''')
    (root / "appcast.xml").write_bytes((root / "appcast-arm64.xml").read_bytes())
    for name in ("weibei.rb", "release-notes.md", f"WeiBei-{VERSION}-debug-symbols.zip"):
        (root / name).write_bytes(b"unit-test fixture")
    refresh_manifest(root, record)
    return record


def refresh_manifest(root, record):
    record["files"] = {path.name: candidate.digest(path) for path in root.iterdir() if path.name != "candidate.json"}
    (root / "candidate.json").write_text(json.dumps(record))


class CandidateBoundaries(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.record = make_candidate(self.root)

    def test_complete_candidate_and_identity_rejection(self):
        self.assertEqual(candidate.verify(self.root, VERSION, SOURCE, "123"), self.record)
        for version, source, run in (("0.0.4", SOURCE, "123"), (VERSION, "b" * 40, "123"), (VERSION, SOURCE, "124")):
            with self.assertRaises(ValueError):
                candidate.verify(self.root, version, source, run)

    def test_changed_bytes_are_rejected(self):
        (self.root / "weibei.rb").write_text("changed")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            candidate.verify(self.root, VERSION, SOURCE)

    def test_rehashed_but_invalid_update_evidence_is_rejected(self):
        path = self.root / "update-verification-arm64.json"
        value = json.loads(path.read_text())
        value["modified_feed_rejected"] = False
        path.write_text(json.dumps(value))
        refresh_manifest(self.root, self.record)
        with self.assertRaisesRegex(ValueError, "signature evidence"):
            candidate.verify(self.root, VERSION, SOURCE)

    def test_rehashed_feed_pointing_elsewhere_is_rejected(self):
        path = self.root / "appcast-x86_64.xml"
        path.write_text(path.read_text().replace("download/v0.0.3", "download/v0.0.2"))
        refresh_manifest(self.root, self.record)
        with self.assertRaisesRegex(ValueError, "feed identity"):
            candidate.verify(self.root, VERSION, SOURCE)

    def test_missing_architecture_or_unexpected_file_is_rejected(self):
        (self.root / "package-x86_64.json").unlink()
        refresh_manifest(self.root, self.record)
        with self.assertRaisesRegex(ValueError, "asset set"):
            candidate.verify(self.root, VERSION, SOURCE)

    def test_workflow_provenance_requires_exact_release_source_and_preparation(self):
        run = {"head_sha": SOURCE, "event": "workflow_dispatch", "path": ".github/workflows/release.yml"}
        jobs = {"jobs": [{"name": "汇总并验证完整候选资产", "conclusion": "success"}]}
        with patch.object(candidate, "gh", side_effect=[json.dumps(run), json.dumps(jobs)]):
            candidate.verify_run("123", SOURCE)
        for changes in ({"head_sha": "b" * 40}, {"event": "pull_request"}, {"path": ".github/workflows/pr-checks.yml"}):
            with patch.object(candidate, "gh", return_value=json.dumps({**run, **changes})), self.assertRaises(ValueError):
                candidate.verify_run("123", SOURCE)
        jobs["jobs"][0]["conclusion"] = "failure"
        with patch.object(candidate, "gh", side_effect=[json.dumps(run), json.dumps(jobs)]), self.assertRaises(ValueError):
            candidate.verify_run("123", SOURCE)

    def test_existing_tag_at_another_source_never_mutates(self):
        with patch.object(candidate, "optional_api", return_value={"sha": "b" * 40}), patch.object(candidate, "gh") as gh:
            with self.assertRaisesRegex(ValueError, "tag points"):
                candidate.publish(self.root, self.record)
            gh.assert_not_called()

    def test_existing_public_candidate_is_idempotent_and_different_bytes_fail(self):
        public = {"target_commitish": SOURCE, "draft": False, "prerelease": False,
                  "assets": [{"name": name, "digest": "sha256:" + self.record["files"][name]} for name in candidate.public_files(VERSION)]}
        with patch.object(candidate, "optional_api", side_effect=[{"sha": SOURCE}, {"tag_name": "v" + VERSION}, public]), patch.object(candidate, "gh") as gh:
            candidate.publish(self.root, self.record)
            gh.assert_not_called()
        public["assets"][0]["digest"] = "sha256:changed"
        with patch.object(candidate, "optional_api", side_effect=[{"sha": SOURCE}, {"tag_name": "v" + VERSION}, public]), patch.object(candidate, "gh") as gh:
            with self.assertRaisesRegex(ValueError, "public asset differs"):
                candidate.publish(self.root, self.record)
            gh.assert_not_called()

    def test_draft_retry_uploads_the_exact_candidate(self):
        draft = {"target_commitish": SOURCE, "draft": True}
        with patch.object(candidate, "optional_api", side_effect=[None, None, draft]), patch.object(candidate, "gh") as gh:
            candidate.publish(self.root, self.record)
            self.assertEqual(gh.call_args_list[0].args[:2], ("release", "upload"))
            self.assertEqual(set(gh.call_args_list[0].args[6:]), {str(self.root / name) for name in candidate.public_files(VERSION)})
            self.assertEqual(gh.call_args_list[-1].args[-1], "--draft=false")

    def test_reused_build_older_than_delivered_update_never_publishes(self):
        feed = io.BytesIO(b'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>20261022.1200.00</sparkle:version></item></channel></rss>')
        with patch.object(candidate, "optional_api", side_effect=[None, {"tag_name": "v0.0.2"}]), patch.object(candidate.urllib.request, "urlopen", return_value=feed), patch.object(candidate, "gh") as gh:
            with self.assertRaisesRegex(ValueError, "no newer"):
                candidate.publish(self.root, self.record)
            gh.assert_not_called()

    def test_network_error_is_not_missing_release(self):
        with patch.object(candidate.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "HTTP 403 forbidden")):
            with self.assertRaises(RuntimeError):
                candidate.optional_api("repo")
        with patch.object(candidate.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "HTTP 404 not found")):
            self.assertIsNone(candidate.optional_api("repo"))


class ReleaseHandoff(unittest.TestCase):
    def test_main_race_is_found_and_rejected_instead_of_waiting_forever(self):
        run = {"displayTitle": "魏碑 / release-request-test", "headSha": "b" * 40}
        with patch.object(release, "matching_runs", return_value=[run]), self.assertRaisesRegex(ValueError, "main advanced"):
            release.request_runs("test", SOURCE)
        with patch.object(release, "matching_runs", return_value=[run]):
            self.assertEqual(release.request_runs("different-request", SOURCE), [])

    def test_exact_head_required_success_and_in_progress_behavior(self):
        pr = {"headRefOid": SOURCE, "baseRefName": "main", "state": "OPEN", "isDraft": False,
              "reviewDecision": "", "mergeStateStatus": "CLEAN", "statusCheckRollup": [
                  {"name": "快速编译与核心自检", "status": "COMPLETED", "conclusion": "SUCCESS"}]}
        self.assertTrue(release.pr_ready(pr, SOURCE))
        with self.assertRaises(ValueError):
            release.pr_ready(pr, "b" * 40)
        for result in ("FAILURE", "CANCELLED", "TIMED_OUT"):
            altered = copy.deepcopy(pr)
            altered["statusCheckRollup"][0]["conclusion"] = result
            with self.assertRaises(ValueError):
                release.pr_ready(altered, SOURCE)
        altered = copy.deepcopy(pr)
        altered["statusCheckRollup"][0].update(status="IN_PROGRESS", conclusion="")
        altered["mergeStateStatus"] = "BLOCKED"
        self.assertFalse(release.pr_ready(altered, SOURCE))
        altered = copy.deepcopy(pr)
        altered["statusCheckRollup"][0]["conclusion"] = "SKIPPED"
        with self.assertRaises(ValueError):
            release.pr_ready(altered, SOURCE)
        for key, value in (("isDraft", True), ("reviewDecision", "CHANGES_REQUESTED"), ("mergeStateStatus", "BEHIND")):
            with self.assertRaises(ValueError):
                release.pr_ready({**pr, key: value}, SOURCE)

    def test_manifest_version_mismatch_is_detected_before_merge(self):
        def content(*args):
            path = args[1].split("/contents/")[1].split("?")[0]
            values = {"VERSION": VERSION, "package.json": json.dumps({"version": VERSION}),
                      "package-lock.json": json.dumps({"version": "0.0.2", "packages": {"": {"version": VERSION}}})}
            return json.dumps({"content": base64.b64encode(values[path].encode()).decode()})
        with patch.object(release, "gh", side_effect=content), self.assertRaisesRegex(ValueError, "reviewed manifests"):
            release.verify_version_at_source(SOURCE, VERSION)

    def test_no_publish_flag_does_not_contact_github(self):
        result = subprocess.run([sys.executable, str(ROOT / "script/release.py"), "--pr", "1", "--reviewed-head", SOURCE, "--version", VERSION], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--publish is required", result.stderr)

    def test_timing_preserves_failure_log_and_exit_code(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = subprocess.run([sys.executable, str(ROOT / "script/timed_run.py"), "--name", "compile",
                "--record", str(root / "timing.jsonl"), "--log", str(root / "build.log"), "--",
                sys.executable, "-c", "print('compiler failed'); raise SystemExit(7)"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 7)
            self.assertIn("compiler failed", result.stdout)
            self.assertEqual((root / "build.log").read_text(), "compiler failed\n")
            self.assertEqual(json.loads((root / "timing.jsonl").read_text())["exit_code"], 7)


if __name__ == "__main__":
    unittest.main()
