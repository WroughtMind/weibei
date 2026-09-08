#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|package|verify) ;; *) echo "usage: $0 [run|package|verify]" >&2; exit 64 ;; esac
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This experiment requires macOS + Xcode/AppKit. Linux syntax checks are not a build." >&2
  exit 69
fi
OUT="$ROOT/.artifacts"
APP="$OUT/WeiBeiChatRendererLab.app"
NAME=WeiBeiChatRendererLab
mkdir -p "$OUT"
LOCK="$OUT/.build-lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "A lab build is already active; do not overwrite it." >&2; exit 75
fi
HIDDEN_BUILD=""
STAGING=""
cleanup() {
  if [[ -n "$HIDDEN_BUILD" && -d "$HIDDEN_BUILD" && ! -e "$ROOT/.build" ]]; then
    mv "$HIDDEN_BUILD" "$ROOT/.build"
  fi
  [[ -z "$STAGING" ]] || rm -rf "$STAGING"
  rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT

# Never terminate WeiBei or a process from another build directory.
python3 - "$APP/Contents/MacOS/$NAME" "$MODE" <<'PY'
import os, signal, subprocess, sys, time
binary, mode = sys.argv[1:]
pids = []
for line in subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True).splitlines():
    fields = line.strip().split(None, 1)
    if len(fields) == 2 and fields[1] == binary:
        pids.append(int(fields[0]))
if pids and mode != 'run':
    raise SystemExit('Close the lab app before replacing its bundle; the production app is untouched.')
for pid in pids:
    os.kill(pid, signal.SIGTERM)
for _ in range(30):
    alive = []
    for pid in pids:
        try: os.kill(pid, 0); alive.append(pid)
        except ProcessLookupError: pass
    if not alive: break
    time.sleep(.1)
else:
    raise SystemExit('The previous lab process did not exit; no bundle was replaced.')
PY
cd "$ROOT"
{
  date -u '+%Y-%m-%dT%H:%M:%SZ'
  uname -m
  sw_vers
  xcodebuild -version
  swift --version
  git rev-parse HEAD
  git status --porcelain
} > "$OUT/environment.txt" 2>&1
swift package resolve 2>&1 | tee "$OUT/resolve.log"
swift build -c release --product "$NAME" 2>&1 | tee "$OUT/build.log"
BIN="$(swift build -c release --show-bin-path)"
swift package show-dependencies --format json > "$OUT/dependencies.json"
cp Package.resolved "$OUT/Package.resolved"

STAGING="$(mktemp -d "$OUT/.bundle-XXXXXX")"
BUNDLE="$STAGING/$NAME.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/ThirdPartyLicenses"
cp "$BIN/$NAME" "$BUNDLE/Contents/MacOS/$NAME"
# Keep resources in the standard location, with root aliases for SwiftPM's
# Bundle.main.bundleURL candidate. Verification hides .build to rule out a
# successful launch accidentally reading an absolute development path.
shopt -s nullglob
for resource in "$BIN"/*.bundle; do
  cp -R "$resource" "$BUNDLE/Contents/Resources/"
  ln -s "Contents/Resources/$(basename "$resource")" "$BUNDLE/$(basename "$resource")"
done
for checkout in "$ROOT/.build/checkouts/"*; do
  [[ -d "$checkout" ]] || continue
  name="$(basename "$checkout")"
  mkdir -p "$BUNDLE/Contents/Resources/ThirdPartyLicenses/$name"
  for license in "$checkout"/LICENSE* "$checkout"/LICENCE* "$checkout"/COPYING*; do
    [[ -f "$license" ]] && cp "$license" "$BUNDLE/Contents/Resources/ThirdPartyLicenses/$name/"
  done
done
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundleIdentifier</key><string>com.weibei.experiments.chat-renderer-lab</string>
<key>CFBundleName</key><string>WeiBei Chat Renderer Lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp "$OUT/environment.txt" "$OUT/Package.resolved" "$BUNDLE/Contents/Resources/"
/usr/bin/plutil -lint "$BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - "$BUNDLE"
/usr/bin/codesign --verify --deep --strict "$BUNDLE"
rm -rf "$APP"
mv "$BUNDLE" "$APP"
/usr/bin/otool -L "$APP/Contents/MacOS/$NAME" > "$OUT/linked-libraries.txt"
echo "Candidate-only bundle: $APP"

if [[ "$MODE" == verify ]]; then
  VERIFY="$OUT/verification"
  mkdir -p "$VERIFY"
  rm -f "$VERIFY/report.json" "$VERIFY/fatal.json"
  HIDDEN_BUILD="$ROOT/.build-resource-check-$$"
  mv "$ROOT/.build" "$HIDDEN_BUILD"
  python3 - "$APP" "$VERIFY" <<'PY'
import json, pathlib, subprocess, sys
app, output = sys.argv[1:]
subprocess.run(['/usr/bin/open', '-n', '-g', '-W', app, '--args', '--verify', output], check=True, timeout=180)
path = pathlib.Path(output) / 'report.json'
if not path.exists():
    failure = pathlib.Path(output) / 'fatal.json'
    raise SystemExit(failure.read_text() if failure.exists() else 'No completion report: inspect the macOS run log.')
report = json.loads(path.read_text())
for check in report['checks']:
    print(('PASS ' if check['passed'] else 'FAIL ') + check['name'] + ': ' + check['detail'])
if not report['checks'] or not all(c['passed'] for c in report['checks']):
    raise SystemExit('Candidate qualification failed. This is not a production A/B result.')
print('Stage A component checks passed; production comparison and user experience are NOT verified.')
PY
  mv "$HIDDEN_BUILD" "$ROOT/.build"
  HIDDEN_BUILD=""
elif [[ "$MODE" == run ]]; then
  /usr/bin/open -n "$APP"
fi
