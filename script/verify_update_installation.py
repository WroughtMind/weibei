#!/usr/bin/env python3
"""Exercise Sparkle against an isolated copy of the signed release candidate on CI."""

import argparse
import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=["arm64", "x86_64"], required=True)
    args = parser.parse_args()
    if os.environ.get("CI") != "true" or platform.machine() != args.arch:
        raise SystemExit("Run update installation only on an isolated native CI runner.")

    repo = Path(__file__).resolve().parent.parent
    version = (repo / "VERSION").read_text().strip()
    release = repo / "dist/release" / args.arch
    dmg = release / f"WeiBei-{version}-macOS-{args.arch}.dmg"
    feed = release / f"appcast-{args.arch}.xml"
    source_app = release / "魏碑.app"
    key = Path(os.environ["WEIBEI_SPARKLE_PRIVATE_KEY_FILE"])
    public_key = os.environ["WEIBEI_SPARKLE_PUBLIC_KEY"]
    sparkle = repo / ".build/catalyst-packages/artifacts/sparkle/Sparkle"
    sign = sparkle / "bin/sign_update"
    framework_dir = sparkle / "Sparkle.xcframework/macos-arm64_x86_64"
    cli_source = repo / ".build/catalyst-packages/checkouts/Sparkle/sparkle-cli"
    evidence = release / f"update-verification-{args.arch}.json"
    log_path = release / f"update-verification-{args.arch}.log"
    log = []

    def run(arguments, *, expect_success=True):
        result = subprocess.run([str(arg) for arg in arguments], capture_output=True, timeout=120)
        output = (result.stdout + result.stderr).decode(errors="replace")
        log.append(f"{Path(arguments[0]).name}: exit={result.returncode}\n{output}")
        if expect_success and result.returncode != 0:
            raise RuntimeError(output)
        return result

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    try:
        with tempfile.TemporaryDirectory(prefix="weibei-update-check-") as temp:
            root = Path(temp)
            tool_app = root / "WeiBeiUpdateCheck.app"
            executable = tool_app / "Contents/MacOS/sparkle"
            executable.parent.mkdir(parents=True)
            run([
                "clang", "-fobjc-arc", "-mmacosx-version-min=14.0",
                "-DSPU_OBJC_DIRECT=__attribute__((objc_direct))",
                "-DSPU_OBJC_DIRECT_MEMBERS=__attribute__((objc_direct_members))",
                "-F", framework_dir, "-framework", "Foundation", "-framework", "AppKit",
                "-framework", "Sparkle", f"-Wl,-rpath,{framework_dir}",
                cli_source / "main.m", cli_source / "SPUCommandLineDriver.m",
                cli_source / "SPUCommandLineUserDriver.m", "-o", executable,
            ])
            (tool_app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": "sparkle",
                "CFBundleIdentifier": "dev.weibei.release-update-check",
                "CFBundleName": "WeiBeiUpdateCheck",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0",
                "LSUIElement": True,
                "NSPrincipalClass": "NSApplication",
                "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True},
            }))
            run(["codesign", "--force", "--sign", "-", tool_app])

            original = plistlib.loads((source_app / "Contents/Info.plist").read_bytes())
            assert original["SUPublicEDKey"] == public_key
            assert original["SURequireSignedFeed"] and original["SUVerifyUpdateBeforeExtraction"]
            assert original["WeiBeiGitCommit"] == os.environ["GITHUB_SHA"]
            original_binary = digest(source_app / "Contents/MacOS/WeiBei")
            target = root / "installed/魏碑.app"
            target.parent.mkdir()
            run(["ditto", "--norsrc", "--noextattr", source_app, target])
            info_path = target / "Contents/Info.plist"
            # Only the copy's build number changes; the production update key stays intact.
            info_path.write_bytes(plistlib.dumps(dict(original, CFBundleVersion="0")))
            run(["codesign", "--force", "--sign", "-", "--preserve-metadata=entitlements,requirements,flags", target])
            run(["codesign", "--verify", "--deep", "--strict", target])

            verifier = root / "public-verifier"
            verifier.write_bytes(base64.b64encode(bytes(64) + base64.b64decode(public_key)))
            tree = ET.parse(feed)
            enclosure = tree.find("./channel/item/enclosure")
            assert enclosure is not None
            signature = enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"]
            assert int(enclosure.attrib["length"]) == dmg.stat().st_size
            run([sign, "--verify", "--ed-key-file", verifier, dmg, signature])
            run([sign, "--verify", "--ed-key-file", verifier, feed])

            damaged = root / "damaged.dmg"
            shutil.copyfile(dmg, damaged)
            with damaged.open("r+b") as stream:
                first = stream.read(1)
                stream.seek(0)
                stream.write(bytes([first[0] ^ 1]))
            assert run([sign, "--verify", "--ed-key-file", verifier, damaged, signature], expect_success=False).returncode != 0
            damaged.unlink()
            damaged_feed = root / "damaged.xml"
            damaged_feed.write_bytes(feed.read_bytes().replace(b"</title>", b" modified</title>", 1))
            assert run([sign, "--verify", "--ed-key-file", verifier, damaged_feed], expect_success=False).returncode != 0

            public = root / "public"
            public.mkdir()
            # Serve the exact candidate bytes, with a separately signed local feed.
            shutil.copyfile(dmg, public / dmg.name)
            requests = []

            class Handler(http.server.SimpleHTTPRequestHandler):
                def __init__(self, *values, **kwargs):
                    super().__init__(*values, directory=str(public), **kwargs)

                def log_message(self, fmt, *values):
                    requests.append(fmt % values)

            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            base_url = f"http://127.0.0.1:{server.server_port}"
            enclosure.set("url", base_url + "/" + dmg.name)
            local_feed = public / "appcast.xml"
            tree.write(local_feed, encoding="utf-8", xml_declaration=True)
            run([sign, "--ed-key-file", key, local_feed])
            run([sign, "--verify", "--ed-key-file", verifier, local_feed])
            threading.Thread(target=server.serve_forever, daemon=True).start()
            try:
                common = ["--feed-url", base_url + "/appcast.xml", "--user-agent-name", "WeiBei release verification", "--verbose"]
                run([executable, target, "--probe", *common])
                run([executable, target, "--application", tool_app, "--check-immediately", "--defer-install", *common])
                deadline = time.monotonic() + 90
                while time.monotonic() < deadline:
                    try:
                        installed = plistlib.loads(info_path.read_bytes())
                        if installed["CFBundleVersion"] == original["CFBundleVersion"]:
                            break
                    except FileNotFoundError:
                        pass
                    time.sleep(0.5)
                else:
                    raise RuntimeError("Sparkle did not install the candidate into the isolated copy.")
                run(["codesign", "--verify", "--deep", "--strict", target])
                assert installed == original
                assert digest(target / "Contents/MacOS/WeiBei") == original_binary
            finally:
                server.shutdown()
                server.server_close()
                log.extend(requests)

            evidence.write_text(json.dumps({
                "passed": True,
                "architecture": args.arch,
                "source_revision": original["WeiBeiGitCommit"],
                "build_number": original["CFBundleVersion"],
                "dmg_sha256": digest(dmg),
                "production_dmg_signature_verified": True,
                "production_feed_signature_verified": True,
                "modified_dmg_rejected": True,
                "modified_feed_rejected": True,
                "actual_sparkle_installation_passed": True,
                "installed_codesign_verified": True,
                "fixture": "Candidate copy with build number 0; production key retained; local feed re-signed with release key.",
                "application_gui_update_tested": False,
            }, ensure_ascii=False, indent=2) + "\n")
            print(evidence.read_text())
    finally:
        log_path.write_text("\n".join(log))


if __name__ == "__main__":
    main()
