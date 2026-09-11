#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  --package) MODE=package ;; --check) MODE=check ;; --verify) MODE=verify ;;
  --debug) MODE=debug ;; --logs) MODE=logs ;; --telemetry) MODE=telemetry ;;
esac
case "$MODE" in
  run|check|package|verify|debug|logs|telemetry) ;;
  *) echo "usage: $0 [run|check|package|verify|debug|logs|telemetry]" >&2; exit 2 ;;
esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
TARGET_ARCH="${WEIBEI_TARGET_ARCH:-$(uname -m)}"
case "$TARGET_ARCH" in arm64|x86_64) ;; *) echo 'build failed: unsupported architecture' >&2; exit 3 ;; esac
CONFIGURATION=Release
[[ "$MODE" != debug ]] || CONFIGURATION=Debug
ACCEPTANCE="${WEIBEI_ACCEPTANCE_CHECKS:-0}"
CONDITIONS=""
[[ "$ACCEPTANCE" != 1 ]] || CONDITIONS=WEIBEI_ACCEPTANCE_CHECKS
[[ "$CONFIGURATION" != Debug ]] || CONDITIONS="$CONDITIONS DEBUG"
SIGNING_IDENTITY="${WEIBEI_SIGNING_IDENTITY:-Apple Development}"
if [[ "${CI:-}" == true && -z "${WEIBEI_SIGNING_IDENTITY:-}" ]]; then SIGNING_IDENTITY=-; fi
BUNDLE_ID="${WEIBEI_BUNDLE_IDENTIFIER:-com.changfenhuang.weibei}"
APP_VERSION="$(tr -d '\r\n' < VERSION)"
BUILD_NUMBER="$(python3 script/build_number.py)"
GIT_COMMIT="$(git rev-parse HEAD)"
SPARKLE_PUBLIC_KEY="${WEIBEI_SPARKLE_PUBLIC_KEY:-eRFPLZuNM6m8bltmtpPX4fzKbufI1z6rKJHtgIIsllk=}"
SPARKLE_FEED_URL="${WEIBEI_SPARKLE_FEED_URL:-https://github.com/WroughtMind/weibei/releases/latest/download/appcast-$TARGET_ARCH.xml}"
DERIVED="$ROOT_DIR/.build/catalyst-$TARGET_ARCH"
PACKAGES="$ROOT_DIR/.build/catalyst-packages"
DIST_DIR="$ROOT_DIR/dist"
[[ "$ACCEPTANCE" != 1 ]] || DIST_DIR="$DIST_DIR/acceptance"
APP_BUNDLE="$DIST_DIR/魏碑.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/WeiBei"
if pgrep -f "^$APP_BINARY( |$)" >/dev/null 2>&1; then
  echo 'build blocked: the target candidate is running; its bundle was preserved' >&2
  exit 4
fi
[[ -x node_modules/.bin/tsx ]] || { echo 'build failed: run npm ci first' >&2; exit 5; }
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'build failed: invalid VERSION' >&2; exit 6; }
[[ "$(printf '%s' "$SPARKLE_PUBLIC_KEY" | base64 -D | wc -c | tr -d ' ')" == 32 ]] || {
  echo 'build failed: Sparkle public key must contain 32 bytes' >&2; exit 7;
}
npm run build:editor >/dev/null
SOURCE_DIRTY=false
[[ -z "$(git status --porcelain=v1 --untracked-files=normal)" ]] || SOURCE_DIRTY=true
mkdir -p "$DERIVED" "$DIST_DIR"
xcodebuild -project App/WeiBei.xcodeproj -scheme WeiBei \
  -clonedSourcePackagesDirPath "$PACKAGES" -onlyUsePackageVersionsFromResolvedFile \
  -resolvePackageDependencies > "$DERIVED/dependencies.log" 2>&1 || {
    tail -30 "$DERIVED/dependencies.log"; exit 8;
  }
MARKDOWN_DIR="$PACKAGES/checkouts/MarkdownView"
TYPOGRAPHY_PATCH="$ROOT_DIR/App/script/markdown-typography.patch"
if ! git -C "$MARKDOWN_DIR" apply --reverse --check "$TYPOGRAPHY_PATCH" 2>/dev/null; then
  git -C "$MARKDOWN_DIR" apply --check "$TYPOGRAPHY_PATCH"
  git -C "$MARKDOWN_DIR" apply "$TYPOGRAPHY_PATCH"
fi
# Recreate final products so removed build phases cannot leave stale embedded code.
rm -rf "$DERIVED/Build/Products/$CONFIGURATION-maccatalyst/魏碑.app" \
  "$DERIVED/Build/Products/$CONFIGURATION/WeiBeiWindowBridge.bundle"
xcodebuild -project App/WeiBei.xcodeproj -scheme WeiBei \
  -configuration "$CONFIGURATION" -destination "platform=macOS,variant=Mac Catalyst,arch=$TARGET_ARCH" \
  -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath "$PACKAGES" \
  -onlyUsePackageVersionsFromResolvedFile \
  "ARCHS=$TARGET_ARCH" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$CONDITIONS" \
  "WEIBEI_TARGET_ARCH=$TARGET_ARCH" "WEIBEI_VERSION=$APP_VERSION" \
  "WEIBEI_BUILD_NUMBER=$BUILD_NUMBER" "WEIBEI_GIT_COMMIT=$GIT_COMMIT" \
  "WEIBEI_SOURCE_DIRTY=$SOURCE_DIRTY" "WEIBEI_BUNDLE_IDENTIFIER=$BUNDLE_ID" \
  "WEIBEI_SPARKLE_FEED_URL=$SPARKLE_FEED_URL" "WEIBEI_SPARKLE_PUBLIC_KEY=$SPARKLE_PUBLIC_KEY" \
  "LAB_BUSINESS_CHECK_ENDPOINT=${WEIBEI_BUSINESS_CHECK_ENDPOINT:-}" \
  build > "$DERIVED/build.log" 2>&1 || {
    awk '/error:|^ld:|BUILD FAILED/ { if (++n <= 30) print }' "$DERIVED/build.log"; exit 9;
  }
BUILT_APP="$DERIVED/Build/Products/$CONFIGURATION-maccatalyst/魏碑.app"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/weibei-catalyst-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
STAGED_APP="$STAGING/魏碑.app"
ditto --norsrc --noextattr "$BUILT_APP" "$STAGED_APP"
CONTENTS="$STAGED_APP/Contents"
PLIST="$CONTENTS/Info.plist"
plutil -replace WeiBeiSourceDirty -bool "$SOURCE_DIRTY" "$PLIST"
plutil -insert WeiBeiAcceptanceChecks -bool "$([[ "$ACCEPTANCE" == 1 ]] && echo true || echo false)" "$PLIST"
mkdir -p "$CONTENTS/Resources/Legal"
# Xcode embeds the locked Sparkle artifact in the native bridge automatically.
[[ -d "$CONTENTS/PlugIns/WeiBeiWindowBridge.bundle/Contents/Frameworks/Sparkle.framework" ]] || {
  echo 'package failed: the update framework is missing from the native bridge' >&2; exit 10;
}
for notice in PRIVACY.md THIRD_PARTY_NOTICES.md ASSET_ATTRIBUTIONS.md; do
  cp "$ROOT_DIR/$notice" "$CONTENTS/Resources/Legal/$notice"
done
# The Catalyst target compiles the layered icon and supplies its Info.plist keys.
for resource in Web/diagram.html Web/mermaid.min.js landscape.png Editor/index.html genui.html AgentResources/system.md; do
  [[ -s "$CONTENTS/Resources/$resource" ]] || { echo "package failed: missing $resource" >&2; exit 10; }
done
DSYM_PATH="$DIST_DIR/WeiBei-$APP_VERSION-$TARGET_ARCH-build-$BUILD_NUMBER-$GIT_COMMIT.dSYM"
ditto --norsrc --noextattr "$BUILT_APP.dSYM" "$DSYM_PATH"
BUILT_UUID="$(dwarfdump --uuid "$CONTENTS/MacOS/WeiBei" | awk 'NR == 1 {print $2}')"
[[ "$BUILT_UUID" == "$(dwarfdump --uuid "$DSYM_PATH" | awk 'NR == 1 {print $2}')" ]] || {
  echo 'package failed: dSYM does not match the app' >&2; exit 11;
}
[[ "$CONFIGURATION" != Release ]] || strip -x "$CONTENTS/MacOS/WeiBei"
xattr -cr "$STAGED_APP"
# Thin all nested code before signing. Keep vendor helper entitlements when re-signing.
python3 - "$STAGED_APP" "$TARGET_ARCH" "$SIGNING_IDENTITY" <<'SIGN'
from pathlib import Path
import os,plistlib,shutil,subprocess,sys
app,arch,identity=Path(sys.argv[1]),sys.argv[2],sys.argv[3]
# Framework headers and module interfaces are compiler inputs, not runtime resources.
for framework in app.rglob('*.framework'):
    for name in ['Headers','PrivateHeaders','Modules']:
        for p in list(framework.rglob(name)):
            if p.is_symlink():p.unlink()
            elif p.is_dir():shutil.rmtree(p)
magic={bytes.fromhex(h) for h in ['feedface','cefaedfe','feedfacf','cffaedfe','cafebabe','bebafeca','cafebabf','bfbafeca']}
files=[p for p in app.rglob('*') if p.is_file() and not p.is_symlink()]
binaries=[]
for p in files:
    with p.open('rb') as f:
        if f.read(4) not in magic:continue
    arches=subprocess.check_output(['lipo','-archs',str(p)],text=True).split()
    if arch not in arches:raise SystemExit(f'package failed: {p} has no {arch}')
    if arches!=[arch]:
        target=p.with_name(p.name+'.thin')
        subprocess.run(['lipo',str(p),'-thin',arch,'-output',str(target)],check=True)
        target.chmod(p.stat().st_mode)
        os.replace(target,p)
    binaries.append(p)
args=['codesign','--force','--options','runtime','--sign',identity,'--preserve-metadata=entitlements']
args+=['--timestamp'] if identity.startswith('Developer ID Application:') else ['--timestamp=none']
bundles=[p for p in app.rglob('*') if p.is_dir() and not p.is_symlink()
         and p.suffix in {'.app','.xpc','.framework','.bundle'}
         and any(p in binary.parents for binary in binaries)]
# Sign bundle executables through their container, after its nested code. Signing
# the main executable directly can inspect still-unsigned siblings on Intel.
main_executables=set()
for bundle in bundles+[app]:
    info=bundle/'Contents/Info.plist'
    executable_dir=bundle/'Contents/MacOS'
    if not info.exists():info=bundle/'Resources/Info.plist'; executable_dir=bundle
    with info.open('rb') as f:executable=plistlib.load(f)['CFBundleExecutable']
    main_executables.add((executable_dir/executable).resolve())
standalone=[p for p in binaries if p.resolve() not in main_executables]
for p in sorted(standalone+bundles,key=lambda p:len(p.parts),reverse=True):
    subprocess.run(args+[str(p)],check=True)
root_args=args
if identity=='-':
    # Ad-hoc code has no Team ID for the runtime-loaded AppKit bridge to share.
    entitlements=app.parent/'adhoc-entitlements.plist'
    entitlements.write_bytes(plistlib.dumps({'com.apple.security.cs.disable-library-validation':True}))
    root_args=args+['--entitlements',str(entitlements)]
subprocess.run(root_args+[str(app)],check=True)
print(f'packaged_architecture={arch}; signed_macho_count={len(binaries)}')
SIGN
codesign --verify --deep --strict "$STAGED_APP"
[[ "$BUILT_UUID" == "$(dwarfdump --uuid "$CONTENTS/MacOS/WeiBei" | awk 'NR == 1 {print $2}')" ]] || {
  echo 'package failed: packaging changed the app UUID' >&2; exit 12;
}
rm -rf "$APP_BUNDLE"
ditto --norsrc --noextattr "$STAGED_APP" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
if [[ "$ACCEPTANCE" != 1 && "$BUNDLE_ID" == com.changfenhuang.weibei && "$CONFIGURATION" == Release ]]; then
  swift run WeiBeiDev verify-release-metadata "$APP_BUNDLE"
  swift run WeiBeiDev verify-release-architecture "$TARGET_ARCH" "$APP_BUNDLE"
  swift run WeiBeiDev verify-production-hygiene "$APP_BUNDLE"
fi
printf 'app=%s\narchitecture=%s\ncommit=%s\n' "$APP_BUNDLE" "$TARGET_ARCH" "$GIT_COMMIT"
case "$MODE" in
  check)
    swift build
    swift run WeiBeiSelfCheck
    swift test --filter WeiBeiSafetyTests
    swift run WeiBeiWebEditorCheck
    ;;
  verify)
    "$ROOT_DIR/script/verify_app_launch.sh" "$APP_BUNDLE"
    ;;
  run) open "$APP_BUNDLE" ;;
  debug) lldb -- "$APP_BINARY" ;;
  logs) open "$APP_BUNDLE"; log stream --info --style compact --predicate 'process == "WeiBei"' ;;
  telemetry) open "$APP_BUNDLE"; log stream --info --style compact --predicate 'subsystem == "com.changfenhuang.weibei"' ;;
esac
