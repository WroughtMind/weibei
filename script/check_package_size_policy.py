#!/usr/bin/env python3
"""Exercise the real macOS metadata verifier on a disposable signed-app copy.

The padded copy is not re-signed or launched. Its metadata may pass regardless of
size, while the independent signature gate must still reject the modified copy.
"""
import argparse
import math
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
# Regression input for the retired 30 MB limit, not a new acceptance threshold.
PADDING_BYTES = 30_000_001


def logical_bytes(app):
    return sum(path.stat().st_size for path in app.rglob('*')
               if path.is_file() and not path.is_symlink())


def run(command):
    return subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)


def expect_result(result, code, message):
    if result.returncode != code or message not in result.stdout + result.stderr:
        raise AssertionError(
            f'expected exit {code} with {message!r}, got {result.returncode}\n'
            f'{result.stdout}{result.stderr}'
        )


def expect_measurement(result, expected_bytes):
    expect_result(result, 0, 'release_metadata_notices=packaged')
    report = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    if int(report['app_logical_bytes']) != expected_bytes:
        raise AssertionError(report)
    if not math.isclose(float(report['app_logical_mb']), expected_bytes / 1_000_000,
                        rel_tol=1e-12):
        raise AssertionError(report)
    if report['app_size_policy'] != 'informational':
        raise AssertionError(report)


def check(app):
    with tempfile.TemporaryDirectory(prefix='weibei-size-policy-') as directory:
        scratch = Path(directory)
        verifier = scratch / 'WeiBeiDev'
        compiled = run(['/usr/bin/xcrun', 'swiftc',
                        str(ROOT / 'Sources/WeiBeiDev/main.swift'),
                        '-module-cache-path', str(scratch / 'ModuleCache'),
                        '-o', str(verifier)])
        expect_result(compiled, 0, '')

        def metadata(path):
            return run([str(verifier), 'verify-release-metadata', '--require-clean', str(path)])

        # A genuine clean-source package is the starting point, not fabricated
        # asset catalogs, fonts or executable headers.
        expect_measurement(metadata(app), logical_bytes(app))
        expect_result(run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)]), 0, '')
        candidate = scratch / '魏碑.app'
        expect_result(run(['/usr/bin/ditto', str(app), str(candidate)]), 0, '')
        original_bytes = logical_bytes(candidate)
        expect_measurement(metadata(candidate), original_bytes)
        expect_result(run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(candidate)]), 0, '')

        padding = candidate / 'Contents/Resources/.size-policy-padding'
        with padding.open('wb') as file:
            file.truncate(PADDING_BYTES)
        padding.with_name('.size-policy-padding-link').symlink_to(padding.name)
        expected_bytes = original_bytes + PADDING_BYTES
        expect_measurement(metadata(candidate), expected_bytes)
        print(f'over_30mb_metadata=passed app_logical_bytes={expected_bytes}')

        # Size acceptance must not make a tampered signed bundle acceptable.
        signature = run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(candidate)])
        if signature.returncode == 0:
            raise AssertionError('signature gate accepted the modified app')
        print('modified_bundle_signature=rejected')

        expect_result(metadata(scratch / 'missing.app'), 4, 'incomplete app bundle')
        print('missing_artifact=rejected')
        info = candidate / 'Contents/Info.plist'
        original_info = info.read_bytes()
        try:
            info.write_bytes(b'not a property list')
            expect_result(metadata(candidate), 8, 'cannot parse Info.plist')
            print('malformed_info_plist=rejected')
            plist = plistlib.loads(original_info)
            plist['WeiBeiGitCommit'] = '0' * 40
            info.write_bytes(plistlib.dumps(plist))
            expect_result(metadata(candidate), 8, 'commit expected')
            print('mismatched_source_commit=rejected')
        finally:
            info.write_bytes(original_info)

        for path, diagnostic, label in [
            (candidate / 'Contents/Resources/Legal/THIRD_PARTY_NOTICES.md',
             'missing packaged notice THIRD_PARTY_NOTICES.md', 'missing_license_notice'),
            (next((candidate / 'Contents/Resources/Editor').glob('KaTeX_*.woff2')),
             'editor must contain all 20 formula fonts', 'missing_formula_font'),
        ]:
            content = path.read_bytes()
            try:
                path.unlink()
                expect_result(metadata(candidate), 10, diagnostic)
                print(f'{label}=rejected')
            finally:
                path.write_bytes(content)
        expect_measurement(metadata(candidate), expected_bytes)
        print('package_size_policy_checks=passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path, help='signed package built from the current clean checkout')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('requires macOS, Xcode tools and an actual signed package; no checks were run')
    check(args.app.resolve())


if __name__ == '__main__':
    main()
