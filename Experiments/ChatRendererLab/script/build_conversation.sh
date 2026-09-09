#!/usr/bin/env bash
set -euo pipefail
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$LAB/../.." && pwd)"
MODE="${1:-package}"
VARIANT="${2:-candidate}"
case "$MODE" in package|verify|benchmark) ;; *) exit 64 ;; esac
case "$VARIANT" in
  candidate) FLAG=CHAT_RENDERER_LAB; NAME='魏碑-会话实验-451'; ID=com.weibei.experiments.conversation451 ;;
  baseline) FLAG=CHAT_RENDERER_BASELINE; NAME='魏碑-会话基线-451'; ID=com.weibei.experiments.conversation451.baseline ;;
  *) exit 64 ;;
esac
[[ "$(uname -s)" == Darwin ]] || { echo '需要 macOS 与 Xcode'; exit 69; }
OUT="$LAB/.artifacts/conversation-$VARIANT"
APP="$OUT/$NAME.app"
mkdir -p "$OUT"
# Refuse to replace this exact running candidate; never stop another app.
python3 - "$APP/Contents/MacOS/WeiBei" <<'PY'
import subprocess, sys
for line in subprocess.check_output(['ps', '-axo', 'comm='], text=True).splitlines():
    if line.strip() == sys.argv[1]:
        raise SystemExit('当前候选仍在运行，请关闭它后重新打包。')
PY
cd "$ROOT"
{
  date -u '+%Y-%m-%dT%H:%M:%SZ'
  git rev-parse HEAD
  git status --porcelain
  sw_vers
  xcodebuild -version
  swift --version
  echo "configuration=Release variant=$VARIANT flag=$FLAG"
} > "$OUT/environment.txt"
[[ -d node_modules ]] || npm ci --no-audit --no-fund > "$OUT/npm-ci.log" 2>&1
npm run build:editor > "$OUT/editor-build.log" 2>&1
swift package resolve > "$OUT/resolve.log" 2>&1
python3 "$LAB/script/prepare_app_resources.py" "$ROOT/.build/checkouts" > "$OUT/dependency-patch.log"
swift build -c release --product WeiBei -Xswiftc "-D$FLAG" > "$OUT/build.log" 2>&1
swift build -c release --product WeiBeiPDFTextWorker -Xswiftc "-D$FLAG" >> "$OUT/build.log" 2>&1
BIN="$(swift build -c release --show-bin-path)"
STAGING="$(mktemp -d "$OUT/.bundle-XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
BUNDLE="$STAGING/$NAME.app"
mkdir -p "$BUNDLE/Contents/"{MacOS,Resources,Frameworks,Helpers}
cp "$BIN/WeiBei" "$BUNDLE/Contents/MacOS/WeiBei"
cp "$BIN/WeiBeiPDFTextWorker" "$BUNDLE/Contents/Helpers/"
ditto --norsrc --noextattr "$BIN/Sparkle.framework" "$BUNDLE/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$BUNDLE/Contents/MacOS/WeiBei"
for resource in "$BIN"/*.bundle; do cp -R "$resource" "$BUNDLE/Contents/Resources/"; done
mkdir -p "$OUT/icon" "$BUNDLE/Contents/Resources/Legal"
xcrun actool --compile "$OUT/icon" --platform macosx --minimum-deployment-target 14.0 \
  --target-device mac --app-icon AppIcon --output-partial-info-plist "$OUT/icon/partial.plist" \
  --standalone-icon-behavior all "$ROOT/DesignSystem/assets/app-icon/AppIcon.icon" > "$OUT/icon-build.log" 2>&1
cp "$OUT/icon/Assets.car" "$OUT/icon/AppIcon.icns" "$BUNDLE/Contents/Resources/"
cp PRIVACY.md THIRD_PARTY_NOTICES.md ASSET_ATTRIBUTIONS.md "$BUNDLE/Contents/Resources/Legal/"
mkdir -p "$BUNDLE/Contents/Resources/ThirdPartyLicenses"
shopt -s nullglob
for checkout in .build/checkouts/*; do
  name="$(basename "$checkout")"
  mkdir -p "$BUNDLE/Contents/Resources/ThirdPartyLicenses/$name"
  for license in "$checkout"/LICENSE* "$checkout"/LICENCE* "$checkout"/COPYING*; do
    [[ ! -f "$license" ]] || cp "$license" "$BUNDLE/Contents/Resources/ThirdPartyLicenses/$name/"
  done
done
cp Package.resolved "$OUT/Package.resolved"
cp "$OUT/Package.resolved" "$OUT/environment.txt" "$BUNDLE/Contents/Resources/"
cp "$LAB/script/prepare_app_resources.py" "$BUNDLE/Contents/Resources/"
cp "$LAB/script/markdownview-weibei.patch" "$BUNDLE/Contents/Resources/"
python3 - "$BUNDLE" "$NAME" "$ID" "$VARIANT" <<'PY'
import pathlib, plistlib, subprocess, sys
app, name, identity, variant = sys.argv[1:]
info = dict(CFBundleExecutable='WeiBei', CFBundleIdentifier=identity, CFBundleName=name,
            CFBundleDisplayName=name, CFBundleIconName='AppIcon', CFBundleIconFile='AppIcon',
            CFBundlePackageType='APPL', CFBundleShortVersionString='0.1.0', CFBundleVersion='451',
            LSMinimumSystemVersion='14.0', NSPrincipalClass='NSApplication', NSHighResolutionCapable=True,
            WeiBeiGitCommit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
            WeiBeiSourceDirty=bool(subprocess.check_output(['git','status','--porcelain'],text=True).strip()),
            WeiBeiExperimentVariant=variant)
with open(pathlib.Path(app)/'Contents/Info.plist','wb') as output: plistlib.dump(info, output)
PY
dsymutil "$BIN/WeiBei" -o "$OUT/WeiBei.dSYM" > "$OUT/dsym.log" 2>&1
BUILD_UUID="$(dwarfdump --uuid "$BIN/WeiBei" | awk 'NR == 1 {print $2}')"
DSYM_UUID="$(dwarfdump --uuid "$OUT/WeiBei.dSYM" | awk 'NR == 1 {print $2}')"
[[ -s "$OUT/WeiBei.dSYM/Contents/Resources/DWARF/WeiBei" && -n "$BUILD_UUID" && "$DSYM_UUID" == "$BUILD_UUID" ]] || {
  echo '候选包的独立调试符号缺失或与构建不匹配' >&2; exit 1;
}
# Match the production packager: keep diagnostics outside the signed app.
PRE_STRIP_BYTES="$(stat -f '%z' "$BUNDLE/Contents/MacOS/WeiBei")"
strip -x "$BUNDLE/Contents/MacOS/WeiBei"
POST_STRIP_BYTES="$(stat -f '%z' "$BUNDLE/Contents/MacOS/WeiBei")"
STRIPPED_UUID="$(dwarfdump --uuid "$BUNDLE/Contents/MacOS/WeiBei" | awk 'NR == 1 {print $2}')"
[[ "$STRIPPED_UUID" == "$BUILD_UUID" && "$POST_STRIP_BYTES" -lt "$PRE_STRIP_BYTES" ]] || {
  echo '候选包的符号清理没有减小体积或改变了构建身份' >&2; exit 1;
}
printf 'before_bytes=%s\nafter_bytes=%s\nuuid=%s\n' "$PRE_STRIP_BYTES" "$POST_STRIP_BYTES" "$BUILD_UUID" > "$OUT/binary-size.txt"
chmod -R u+w "$BUNDLE/Contents/Resources"
# Both MarkdownView's MTMathImage and native chat use the complete Latin Modern font.
find "$BUNDLE/Contents/Resources/SwiftMath_SwiftMath.bundle/mathFonts.bundle" -type f \
  \( -name '*.otf' -o -name '*.plist' -o -name 'math_table_to_plist.py' \) \
  ! -name 'latinmodern-math.otf' ! -name 'latinmodern-math.plist' -delete
# Highlightr initializes with pojoaque, then MarkdownView selects xcode for both appearances.
find "$BUNDLE/Contents/Resources/Highlightr_Highlightr.bundle" -type f -name '*.css' \
  ! -name 'pojoaque.min.css' ! -name 'xcode.min.css' -delete
xattr -cr "$BUNDLE"
codesign --force --deep --sign - --timestamp=none "$BUNDLE/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --timestamp=none "$BUNDLE/Contents/Helpers/WeiBeiPDFTextWorker"
codesign --force --sign - --timestamp=none "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
rm -rf "$APP"
mv "$BUNDLE" "$APP"
shasum -a 256 "$APP/Contents/MacOS/WeiBei" > "$OUT/binary-sha256.txt"
echo "$APP"
if [[ "$MODE" == verify ]]; then
  [[ "$VARIANT" == candidate ]] || { echo '基线仅作独立人工比较'; exit 64; }
  VERIFY="$(mktemp -d "$OUT/check-XXXXXX")"
  # Force the app to prove its packaged resources without the development tree.
  HIDDEN="$ROOT/.build-conversation-resource-check-$$"
  mv "$ROOT/.build" "$HIDDEN"
  trap '[[ ! -d "$HIDDEN" ]] || mv "$HIDDEN" "$ROOT/.build"; rm -rf "$STAGING"' EXIT
  python3 - "$APP" "$VERIFY" <<'PY'
import json, pathlib, subprocess, sys
app, output = sys.argv[1:]
subprocess.run(['/usr/bin/open','-n','-g','-W','--stdout',output+'/stdout.log','--stderr',output+'/stderr.log',
                app,'--args','--chat-renderer-verify',output], check=True, timeout=240)
report = pathlib.Path(output)/'conversation-report.json'
if not report.exists(): raise SystemExit('没有完成报告，请检查 '+output)
data = json.loads(report.read_text())
for check in data['checks']: print(check)
if not data['checks'] or not all(c['passed'] for c in data['checks']): raise SystemExit('真实会话检查失败：'+str(report))
print(report)
PY
  mv "$HIDDEN" "$ROOT/.build"
fi

if [[ "$MODE" == benchmark ]]; then
  for SCENARIO in 0 1 2; do
    EVIDENCE="$(mktemp -d "$OUT/evidence-$SCENARIO-XXXXXX")"
    python3 - "$APP" "$EVIDENCE" "$SCENARIO" <<'PYBENCH'
import pathlib, subprocess, sys
app, output, scenario = sys.argv[1:]
subprocess.run(['/usr/bin/open','-n','-g','-W','--stdout',output+'/stdout.log','--stderr',output+'/stderr.log',
                app,'--args','--chat-renderer-benchmark',output,scenario], check=True, timeout=180)
report=pathlib.Path(output)/'pane-evidence.json'
if not report.exists(): raise SystemExit('没有性能记录：'+output)
print(report.read_text())
PYBENCH
  done
fi
