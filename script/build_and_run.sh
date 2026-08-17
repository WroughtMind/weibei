#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PACKAGE_ONLY=false
if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  MODE="package"
  PACKAGE_ONLY=true
fi
CHECK_ONLY=false
if [[ "$MODE" == "--check" || "$MODE" == "check" ]]; then
  MODE="check"
  CHECK_ONLY=true
fi
PRODUCT_NAME="WeiBei"
APP_DISPLAY_NAME="魏碑"
BUNDLE_ID="com.changfenhuang.weibei"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="release"
if [[ "$MODE" == "check" || "$MODE" == "--debug" || "$MODE" == "debug" ]]; then
  BUILD_CONFIGURATION="debug"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
FINAL_DIST_DIR="$ROOT_DIR/dist"
FINAL_APP_BUNDLE="$FINAL_DIST_DIR/$APP_DISPLAY_NAME.app"
FINAL_APP_BINARY="$FINAL_APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
# Always assemble + codesign outside the repo tree. Projects under ~/Documents
# (iCloud / File Provider) get com.apple.FinderInfo and related xattrs stamped
# onto the bundle; codesign then fails with "resource fork, Finder information,
# or similar detritus not allowed".
if [[ "$PACKAGE_ONLY" == true ]]; then
  DIST_DIR="${TMPDIR:-/tmp}/weibei-package-$UID"
else
  DIST_DIR="${TMPDIR:-/tmp}/weibei-run-$UID"
fi
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_ICON_SOURCE="$ROOT_DIR/DesignSystem/assets/app-icon/AppIcon.icns"
# Current pre-release packages ship only active legal notices. Future release
# plans such as Docs/releases/v1.0.0.md stay in the repo and are not packaged.
LEGAL_SOURCE_FILES=(
  "$ROOT_DIR/PRIVACY.md"
  "$ROOT_DIR/THIRD_PARTY_NOTICES.md"
  "$ROOT_DIR/ASSET_ATTRIBUTIONS.md"
)
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
FINAL_AUDIT_DIR="$DIST_DIR/final-audit"
FINAL_AUDIT_APP_BUNDLE="$FINAL_AUDIT_DIR/$APP_DISPLAY_NAME.app"
FINAL_AUDIT_APP_BINARY="$FINAL_AUDIT_APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
PDF_TEXT_WORKER_NAME="WeiBeiPDFTextWorker"
PDF_TEXT_WORKER="$APP_HELPERS/$PDF_TEXT_WORKER_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

target_app_is_running() {
  local pid command target_binary="$APP_BINARY"
  if [[ "$PACKAGE_ONLY" == true ]]; then
    target_binary="$FINAL_APP_BINARY"
  fi
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$command" == "$target_binary" || "$command" == "$target_binary "* ]]; then
      return 0
    fi
  done < <(pgrep -x "$PRODUCT_NAME" 2>/dev/null || true)
  return 1
}

if [[ "$CHECK_ONLY" == true ]]; then
  :
elif [[ "$PACKAGE_ONLY" == true ]]; then
  if target_app_is_running; then
    echo "package blocked: $APP_DISPLAY_NAME is running; quit it first so dist can be replaced without touching the active window." >&2
    exit 6
  fi
else
  pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true
  for _ in {1..50}; do
    pgrep -x "$PRODUCT_NAME" >/dev/null || break
    sleep 0.1
  done
fi

if [[ -d "$ROOT_DIR/node_modules" ]]; then
  npm run build:editor >/dev/null
elif [[ "$CHECK_ONLY" == true || "$PACKAGE_ONLY" == true ]]; then
  echo "build failed: run npm ci first" >&2
  exit 25
fi

if [[ "$CHECK_ONLY" != true ]]; then
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "build failed: missing VERSION" >&2
    exit 19
  fi
  APP_VERSION="$(/usr/bin/tr -d '\r\n' <"$VERSION_FILE")"
  if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "build failed: VERSION must use numeric major.minor.patch" >&2
    exit 20
  fi
  if [[ "$(git -C "$ROOT_DIR" rev-parse --is-shallow-repository)" == "true" ]]; then
    echo "build failed: full Git history is required for a stable build number" >&2
    exit 21
  fi
  GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --verify HEAD)"
  BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count "$GIT_COMMIT")"
  SOURCE_DIRTY=false
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=normal)" ]]; then
    SOURCE_DIRTY=true
  fi
fi

PI_RUNTIME_DIR="$("$ROOT_DIR/script/prepare_pi_runtime.sh")"
PI_RUNTIME_BINARY="$PI_RUNTIME_DIR/bin/pi"
PI_RUNTIME_VERSION="$(/usr/bin/plutil -extract piVersion raw -o - "$PI_RUNTIME_DIR/manifest.json")"
if [[ ! -x "$PI_RUNTIME_BINARY" ]]; then
  echo "build failed: embedded PI runtime was not prepared" >&2
  exit 8
fi

pi_reports_expected_version() {
  local executable="$1" attempt reported_version
  for attempt in {1..10}; do
    reported_version="$("$executable" --version 2>/dev/null || true)"
    if [[ "$reported_version" == "$PI_RUNTIME_VERSION" ]]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

swift build -c "$BUILD_CONFIGURATION"

if [[ "$CHECK_ONLY" != true ]]; then
  BUILD_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
  BUILD_BINARY="$BUILD_DIR/$PRODUCT_NAME"
  RESOURCE_BUNDLES=(
    "$BUILD_DIR/${PRODUCT_NAME}_${PRODUCT_NAME}.bundle"
    "$BUILD_DIR/${PRODUCT_NAME}_WeiBeiCore.bundle"
  )

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_HELPERS" "$APP_RESOURCES"
  if [[ ! -f "$APP_ICON_SOURCE" ]]; then
    echo "package failed: missing App Icon at $APP_ICON_SOURCE" >&2
    exit 22
  fi
  cp "$BUILD_BINARY" "$APP_BINARY"
  if ! /usr/bin/cmp -s "$BUILD_BINARY" "$APP_BINARY"; then
    echo "package failed: copied app binary does not match the current Swift build" >&2
    exit 10
  fi
  chmod +x "$APP_BINARY"
  BUILD_PDF_TEXT_WORKER="$BUILD_DIR/$PDF_TEXT_WORKER_NAME"
  if [[ ! -x "$BUILD_PDF_TEXT_WORKER" ]]; then
    echo "package failed: missing bounded PDF text worker" >&2
    exit 12
  fi
  cp "$BUILD_PDF_TEXT_WORKER" "$PDF_TEXT_WORKER"
  if ! /usr/bin/cmp -s "$BUILD_PDF_TEXT_WORKER" "$PDF_TEXT_WORKER"; then
    echo "package failed: copied PDF text worker does not match the current Swift build" >&2
    exit 13
  fi
  chmod +x "$PDF_TEXT_WORKER"
  for resource_bundle in "${RESOURCE_BUNDLES[@]}"; do
    if [[ ! -d "$resource_bundle" ]]; then
      echo "package failed: missing resource bundle $resource_bundle" >&2
      exit 7
    fi
    cp -R "$resource_bundle" "$APP_RESOURCES/"
  done
  PACKAGED_PI_ROOT="$APP_RESOURCES/PiRuntime"
  mkdir -p "$PACKAGED_PI_ROOT/bin"
  cp "$PI_RUNTIME_DIR/bin/pi" "$PACKAGED_PI_ROOT/bin/pi"
  cp "$PI_RUNTIME_DIR/bin/package.json" "$PACKAGED_PI_ROOT/bin/package.json"
  cp -R "$PI_RUNTIME_DIR/bin/theme" "$PACKAGED_PI_ROOT/bin/theme"
  for pi_metadata in manifest.json LICENSE THIRD_PARTY_NOTICES.md BUN_LICENSE.md artifact.sha256 binary.sha256; do
    if [[ ! -f "$PI_RUNTIME_DIR/$pi_metadata" ]]; then
      echo "package failed: embedded PI runtime is missing $pi_metadata" >&2
      exit 23
    fi
    cp "$PI_RUNTIME_DIR/$pi_metadata" "$PACKAGED_PI_ROOT/$pi_metadata"
  done
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
  mkdir -p "$APP_RESOURCES/Legal"
  for legal_source in "${LEGAL_SOURCE_FILES[@]}"; do
    if [[ ! -f "$legal_source" ]]; then
      echo "package failed: missing legal/release notice $legal_source" >&2
      exit 24
    fi
    cp "$legal_source" "$APP_RESOURCES/Legal/$(basename "$legal_source")"
  done
  # Clear inherited provenance/quarantine metadata before executing the copied
  # Bun-based Pi binary. Downloaded DMGs receive a fresh quarantine marker on
  # the user's Mac; README documents the separate first-launch approval flow.
  /usr/bin/xattr -cr "$APP_BUNDLE"

  PACKAGED_PI="$APP_RESOURCES/PiRuntime/bin/pi"
  # Re-seal the copied executable at its final path. On macOS, a freshly copied
  # ad-hoc binary can otherwise be killed by policy evaluation on its first launch.
  /usr/bin/codesign --force --sign - --timestamp=none "$PACKAGED_PI" >/dev/null
  if [[ ! -x "$PACKAGED_PI" ]] \
    || [[ ! -f "$APP_RESOURCES/PiRuntime/manifest.json" ]] \
    || [[ ! -f "$APP_RESOURCES/PiRuntime/LICENSE" ]] \
    || [[ ! -f "$APP_RESOURCES/PiRuntime/THIRD_PARTY_NOTICES.md" ]] \
    || [[ ! -f "$APP_RESOURCES/PiRuntime/binary.sha256" ]] \
    || ! /usr/bin/codesign --verify --strict "$PACKAGED_PI" >/dev/null 2>&1 \
    || [[ "$(/usr/bin/shasum -a 256 "$PACKAGED_PI" | /usr/bin/awk '{print $1}')" != "$(<"$APP_RESOURCES/PiRuntime/binary.sha256")" ]] \
    || ! pi_reports_expected_version "$PACKAGED_PI"; then
    echo "package failed: embedded PI runtime is incomplete" >&2
    exit 9
  fi

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>WeiBeiGitCommit</key>
  <string>$GIT_COMMIT</string>
  <key>WeiBeiSourceDirty</key>
  <$SOURCE_DIRTY/>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
  /usr/bin/codesign --force --sign - --timestamp=none "$PDF_TEXT_WORKER" >/dev/null
  /usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null
  if ! /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null; then
    echo "package failed: staged app signature is invalid at $APP_BUNDLE" >&2
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -20 >&2 || true
    exit 19
  fi
  BUILD_UUID="$(/usr/bin/dwarfdump --uuid "$BUILD_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
  PACKAGED_UUID="$(/usr/bin/dwarfdump --uuid "$APP_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
  if [[ -z "$BUILD_UUID" || "$PACKAGED_UUID" != "$BUILD_UUID" ]]; then
    echo "package failed: signed app binary UUID does not match the current Swift build" >&2
    exit 11
  fi
  WEIBEI_PI_EXECUTABLE="$PACKAGED_PI" WEIBEI_PI_APP_BUNDLE="$APP_BUNDLE" WEIBEI_PI_LIVE_CHECK=0 \
    "$BUILD_DIR/WeiBeiPiCheck"
  # Mirror a clean copy into repo dist/ for inspection. Launch always uses the
  # staged /tmp bundle (valid signature); Documents copies can re-acquire
  # File Provider xattrs that invalidate codesign verification.
  rm -rf "$FINAL_APP_BUNDLE"
  mkdir -p "$FINAL_DIST_DIR"
  /usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$FINAL_APP_BUNDLE"
  /usr/bin/xattr -cr "$FINAL_APP_BUNDLE" 2>/dev/null || true
  if ! /usr/bin/cmp -s "$APP_BINARY" "$FINAL_APP_BINARY"; then
    echo "package failed: final app binary changed while copying from signed staging" >&2
    exit 15
  fi
  if [[ "$PACKAGE_ONLY" == true ]]; then
    if ! /usr/bin/codesign --verify --deep "$FINAL_APP_BUNDLE" >/dev/null 2>&1; then
      # Documents may stamp FinderInfo onto the published copy; re-seal in place
      # after stripping attrs so release consumers still get a verifiable dist/.
      /usr/bin/xattr -cr "$FINAL_APP_BUNDLE" 2>/dev/null || true
      /usr/bin/codesign --force --sign - --timestamp=none "$FINAL_APP_BUNDLE/Contents/Resources/PiRuntime/bin/pi" >/dev/null 2>&1 || true
      /usr/bin/codesign --force --sign - --timestamp=none "$FINAL_APP_BUNDLE/Contents/Helpers/$PDF_TEXT_WORKER_NAME" >/dev/null 2>&1 || true
      /usr/bin/codesign --force --sign - --timestamp=none "$FINAL_APP_BUNDLE" >/dev/null
    fi
    /usr/bin/codesign --verify --deep "$FINAL_APP_BUNDLE"
    FINAL_UUID="$(/usr/bin/dwarfdump --uuid "$FINAL_APP_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
    if [[ -z "$FINAL_UUID" || "$FINAL_UUID" != "$PACKAGED_UUID" ]]; then
      echo "package failed: final app binary UUID changed while copying from signed staging" >&2
      exit 16
    fi
    rm -rf "$FINAL_AUDIT_DIR"
    mkdir -p "$FINAL_AUDIT_DIR"
    /usr/bin/ditto --norsrc --noextattr "$FINAL_APP_BUNDLE" "$FINAL_AUDIT_APP_BUNDLE"
    /usr/bin/xattr -cr "$FINAL_AUDIT_APP_BUNDLE"
    /usr/bin/codesign --verify --deep --strict "$FINAL_AUDIT_APP_BUNDLE"
    if ! /usr/bin/cmp -s "$FINAL_APP_BINARY" "$FINAL_AUDIT_APP_BINARY"; then
      echo "package failed: strict-audit copy changed the final app binary" >&2
      exit 17
    fi
    AUDITED_UUID="$(/usr/bin/dwarfdump --uuid "$FINAL_AUDIT_APP_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
    if [[ -z "$AUDITED_UUID" || "$AUDITED_UUID" != "$FINAL_UUID" ]]; then
      echo "package failed: strict-audit copy changed the final app binary UUID" >&2
      exit 18
    fi
    (cd "$ROOT_DIR" && swift run WeiBeiDev verify-release-metadata "$FINAL_APP_BUNDLE")
    (cd "$ROOT_DIR" && swift run WeiBeiDev verify-production-hygiene "$FINAL_APP_BUNDLE")
  fi
fi

open_app() {
  # Launch the staged, validly signed bundle — not dist/ under Documents.
  if ! /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
    echo "open blocked: staged app signature invalid at $APP_BUNDLE" >&2
    exit 20
  fi
  /usr/bin/open "$APP_BUNDLE"
}

run_verifiers() {
  WEIBEI_PI_EXECUTABLE="$PI_RUNTIME_BINARY" \
    swift run -c "$BUILD_CONFIGURATION" WeiBeiSelfCheck
  swift test -c "$BUILD_CONFIGURATION" --filter WeiBeiSafetyTests
  swift run -c "$BUILD_CONFIGURATION" WeiBeiWebEditorCheck
  WEIBEI_PI_EXECUTABLE="$PI_RUNTIME_BINARY" \
    swift run -c "$BUILD_CONFIGURATION" WeiBeiPiCheck
}

case "$MODE" in
  check)
    run_verifiers
    ;;
  package)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PRODUCT_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  *)
    echo "usage: $0 [run|check|package|--debug|--logs|--telemetry]" >&2
    exit 2
    ;;
esac
