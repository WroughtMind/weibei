#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
RUN_VISUAL_VERIFY=false
if [[ "$MODE" == "--visual-verify" || "$MODE" == "visual-verify" ]]; then
  MODE="--visual-verify"
  RUN_VISUAL_VERIFY=true
fi
if [[ "${2:-}" == "--visual-verify" || "${2:-}" == "visual-verify" ]]; then
  RUN_VISUAL_VERIFY=true
fi
PACKAGE_ONLY=false
if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  MODE="package"
  PACKAGE_ONLY=true
fi
CHECK_ONLY=false
if [[ "$MODE" == "--check" || "$MODE" == "check" || "$MODE" == "--verify-only" || "$MODE" == "verify-only" ]]; then
  MODE="check"
  CHECK_ONLY=true
fi
VERIFY_MODE=false
if [[ "$MODE" == "--verify" || "$MODE" == "verify" || "$MODE" == "--visual-verify" || "$MODE" == "visual-verify" ]]; then
  VERIFY_MODE=true
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
if [[ "$VERIFY_MODE" == true ]]; then
  DIST_DIR="${TMPDIR:-/tmp}/weibei-verify-$UID-$$"
elif [[ "$PACKAGE_ONLY" == true ]]; then
  DIST_DIR="${TMPDIR:-/tmp}/weibei-package-$UID"
else
  DIST_DIR="$FINAL_DIST_DIR"
fi
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_ICON_SOURCE="$ROOT_DIR/DesignSystem/assets/app-icon/AppIcon.icns"
LEGAL_SOURCE_FILES=(
  "$ROOT_DIR/PRIVACY.md"
  "$ROOT_DIR/THIRD_PARTY_NOTICES.md"
  "$ROOT_DIR/ASSET_ATTRIBUTIONS.md"
  "$ROOT_DIR/Docs/releases/v1.0.0.md"
)
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
FINAL_AUDIT_DIR="$DIST_DIR/final-audit"
FINAL_AUDIT_APP_BUNDLE="$FINAL_AUDIT_DIR/$APP_DISPLAY_NAME.app"
FINAL_AUDIT_APP_BINARY="$FINAL_AUDIT_APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
PDF_TEXT_WORKER_NAME="WeiBeiPDFTextWorker"
PDF_TEXT_WORKER="$APP_HELPERS/$PDF_TEXT_WORKER_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
VERIFY_PID=""
VERIFY_DATA_DIR="$DIST_DIR/Data"
VERIFY_STDOUT="$VERIFY_DATA_DIR/app-stdout.log"
VERIFY_STDERR="$VERIFY_DATA_DIR/app-stderr.log"
VERIFY_SCENARIO="${WEIBEI_VERIFY_SCENARIO:-offline-learning-flow}"
VERIFY_WINDOW_SIZE="${WEIBEI_VERIFY_WINDOW_SIZE:-}"
VERIFY_INSPIRATION_ID="${WEIBEI_VERIFY_INSPIRATION_ID:-}"
VERIFY_CAPTURE_PATH="${TMPDIR:-/tmp}/weibei-self-capture-$UID-$$-$VERIFY_SCENARIO.png"

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
elif [[ "$VERIFY_MODE" == true ]]; then
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

if [[ "$CHECK_ONLY" == true ]]; then
  if [[ -d "$ROOT_DIR/node_modules" && -d "$ROOT_DIR/Prototypes/RichAnswerWebRuntime/node_modules" ]]; then
    npm run check
  elif [[ -d "$ROOT_DIR/node_modules" || -d "$ROOT_DIR/Prototypes/RichAnswerWebRuntime/node_modules" ]]; then
    echo "check failed: Node dependencies are only partially installed; run npm ci at the repository root and in Prototypes/RichAnswerWebRuntime" >&2
    exit 25
  else
    echo "Node checks skipped: dependencies are not installed; CI runs them in the generated-resources job."
  fi
else
  if [[ -d "$ROOT_DIR/node_modules" ]]; then
    npm run build:editor >/dev/null
  fi
  if [[ -d "$ROOT_DIR/Prototypes/RichAnswerWebRuntime/node_modules" ]]; then
    npm run build:rich-answer >/dev/null
  fi
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
  for pi_metadata in manifest.json LICENSE THIRD_PARTY_NOTICES.md artifact.sha256 binary.sha256; do
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
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  if [[ "$(/usr/bin/env WEIBEI_PDF_WORKER_VERIFY=1 "$PDF_TEXT_WORKER" --verification-probe normal)" != "verification-ok" ]]; then
    echo "package failed: signed PDF text worker did not complete its runtime probe" >&2
    exit 14
  fi
  BUILD_UUID="$(/usr/bin/dwarfdump --uuid "$BUILD_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
  PACKAGED_UUID="$(/usr/bin/dwarfdump --uuid "$APP_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
  if [[ -z "$BUILD_UUID" || "$PACKAGED_UUID" != "$BUILD_UUID" ]]; then
    echo "package failed: signed app binary UUID does not match the current Swift build" >&2
    exit 11
  fi
  WEIBEI_PI_EXECUTABLE="$PACKAGED_PI" WEIBEI_PI_APP_BUNDLE="$APP_BUNDLE" WEIBEI_PI_LIVE_CHECK=0 \
    "$BUILD_DIR/WeiBeiPiCheck"
  if [[ "$PACKAGE_ONLY" == true ]]; then
    rm -rf "$FINAL_APP_BUNDLE"
    mkdir -p "$FINAL_DIST_DIR"
    /usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$FINAL_APP_BUNDLE"
    /usr/bin/xattr -cr "$FINAL_APP_BUNDLE"
    if ! /usr/bin/cmp -s "$APP_BINARY" "$FINAL_APP_BINARY"; then
      echo "package failed: final app binary changed while copying from signed staging" >&2
      exit 15
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
    "$ROOT_DIR/script/verify_release_metadata.sh" "$FINAL_APP_BUNDLE"
  fi
fi

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

cleanup_verify_app() {
  if [[ "$VERIFY_MODE" == true && -n "${VERIFY_PID:-}" ]]; then
    kill "$VERIFY_PID" >/dev/null 2>&1 || true
  fi
}

open_app_for_verify() {
  local agent_environment=(WEIBEI_FORCE_OFFLINE_AGENT=1)
  local pane_trace_dir=""
  local pane_trace_samples=0
  if [[ "$VERIFY_SCENARIO" == "pi-learning-flow" || "$VERIFY_SCENARIO" == "pi-course-memory-flow" ]]; then
    agent_environment=(
      WEIBEI_FORCE_OFFLINE_AGENT=0
      WEIBEI_PI_PROVIDER=openai-codex
      WEIBEI_PI_MODEL=gpt-5.5
    )
  fi
  if [[ "$VERIFY_SCENARIO" == "pane-layout-stability-flow" || "$VERIFY_SCENARIO" == "pane-toggle-continuity-flow" || "$VERIFY_SCENARIO" == "pane-reorder-width-flow" ]]; then
    pane_trace_dir="$VERIFY_DATA_DIR/pane-trace"
  fi
  if [[ "$VERIFY_SCENARIO" == "pane-layout-stability-flow" ]]; then
    pane_trace_samples=1
  fi
  rm -rf "$VERIFY_DATA_DIR"
  mkdir -p "$VERIFY_DATA_DIR"
  rm -f "$VERIFY_CAPTURE_PATH"
  /usr/bin/env \
    WEIBEI_SUPPRESS_ACTIVATION=1 \
    "${agent_environment[@]}" \
    "WEIBEI_WORKSPACE_DIR=$VERIFY_DATA_DIR" \
    "WEIBEI_VERIFY_SCENARIO=$VERIFY_SCENARIO" \
    "WEIBEI_VERIFY_WINDOW_SIZE=$VERIFY_WINDOW_SIZE" \
    "WEIBEI_VERIFY_INSPIRATION_ID=$VERIFY_INSPIRATION_ID" \
    "WEIBEI_VERIFY_CAPTURE_PATH=$VERIFY_CAPTURE_PATH" \
    "WEIBEI_VERIFY_PANE_TRACE_DIR=$pane_trace_dir" \
    "WEIBEI_VERIFY_PANE_TRACE_SAMPLES=$pane_trace_samples" \
    "$APP_BINARY" >"$VERIFY_STDOUT" 2>"$VERIFY_STDERR" &
  VERIFY_PID="$!"
  trap cleanup_verify_app EXIT
  for _ in {1..50}; do
    if kill -0 "$VERIFY_PID" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  echo "verify launch failed: signed $APP_DISPLAY_NAME process exited before opening a window." >&2
  [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
  return 1
}

verify_window() {
  swift -e 'import CoreGraphics; import Foundation; let owner = CommandLine.arguments[1]; let targetPID = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) : nil; func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }; let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []; let found = windows.contains { window in guard (window[kCGWindowOwnerName as String] as? String) == owner else { return false }; if let targetPID, (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue != targetPID { return false }; let bounds = window[kCGWindowBounds as String] as? [String: Any]; let isOnscreen = window[kCGWindowIsOnscreen as String] as? NSNumber; let visibleEnough = isOnscreen == nil || isOnscreen?.intValue != 0; return visibleEnough && number(window[kCGWindowLayer as String]) == 0 && number(bounds?["Width"]) >= 600 && number(bounds?["Height"]) >= 400 }; if !found { exit(1) }' "$APP_DISPLAY_NAME" "$VERIFY_PID"
}

visual_verify_window() {
  if [[ -n "$VERIFY_SCENARIO" ]]; then
    for _ in {1..50}; do
      if [[ -s "$VERIFY_CAPTURE_PATH" ]] \
        && /usr/bin/sips -g pixelWidth -g pixelHeight "$VERIFY_CAPTURE_PATH" >/dev/null 2>&1; then
        break
      fi
      sleep 0.2
    done
  fi
  local capture_path="$VERIFY_CAPTURE_PATH"
  if [[ ! -s "$capture_path" ]]; then
    local window_id
    window_id="$(swift -target arm64-apple-macosx14.0 -e 'import CoreGraphics; import Foundation; let owner = CommandLine.arguments[1]; let targetPID = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) : nil; func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }; let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []; guard let window = windows.first(where: { window in guard (window[kCGWindowOwnerName as String] as? String) == owner else { return false }; if let targetPID, (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue != targetPID { return false }; let bounds = window[kCGWindowBounds as String] as? [String: Any]; let isOnscreen = window[kCGWindowIsOnscreen as String] as? NSNumber; let visibleEnough = isOnscreen == nil || isOnscreen?.intValue != 0; return visibleEnough && number(window[kCGWindowLayer as String]) == 0 && number(bounds?["Width"]) >= 600 && number(bounds?["Height"]) >= 400 }), let id = window[kCGWindowNumber as String] as? UInt32 else { exit(1) }; print(id)' "$APP_DISPLAY_NAME" "$VERIFY_PID")"
    capture_path="${TMPDIR:-/tmp}/weibei-visual-verify-$window_id.png"
    local capture_error="${TMPDIR:-/tmp}/weibei-visual-verify-$window_id.err"
    if ! /usr/sbin/screencapture -x -l "$window_id" "$capture_path" 2>"$capture_error"; then
      cat "$capture_error" >&2
      echo "visual verify blocked: both the app-owned capture and macOS window capture failed for $APP_DISPLAY_NAME. Grant Screen Recording permission to this terminal/Codex host, then rerun --visual-verify." >&2
      rm -f "$capture_path" "$capture_error"
      exit 5
    fi
    rm -f "$capture_error"
  fi
  swift -target arm64-apple-macosx14.0 -e 'import AppKit; import Foundation; let path = CommandLine.arguments[1]; guard let image = NSImage(contentsOf: URL(fileURLWithPath: path)), let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { exit(2) }; let xStep = max(1, bitmap.pixelsWide / 80); let yStep = max(1, bitmap.pixelsHigh / 60); var sampled = 0; var visible = 0; var black = 0; var transparent = 0; for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStep) { for x in stride(from: 0, to: bitmap.pixelsWide, by: xStep) { guard let color = bitmap.colorAt(x: x, y: y) else { continue }; if color.redComponent > 0.08 || color.greenComponent > 0.08 || color.blueComponent > 0.08 { visible += 1 }; if color.redComponent < 0.035 && color.greenComponent < 0.035 && color.blueComponent < 0.035 { black += 1 }; if color.alphaComponent < 0.05 { transparent += 1 }; sampled += 1 } }; guard sampled > 0 else { exit(3) }; let nonBlackRatio = Double(visible) / Double(sampled); let blackRatio = Double(black) / Double(sampled); let transparentRatio = Double(transparent) / Double(sampled); print("visual_non_black_ratio=\(nonBlackRatio)"); print("visual_black_ratio=\(blackRatio)"); print("visual_transparent_ratio=\(transparentRatio)"); if nonBlackRatio < 0.02 || blackRatio > 0.12 || transparentRatio > 0.005 { fputs("visual verify failed: captured window is empty, transparent, or contains black rendering blocks\n", stderr); exit(4) }' "$capture_path"
  local latest_capture_path="${TMPDIR:-/tmp}/weibei-visual-verify-latest.png"
  local scenario_capture_path="${TMPDIR:-/tmp}/weibei-visual-verify-$VERIFY_SCENARIO.png"
  cp "$capture_path" "$latest_capture_path"
  cp "$capture_path" "$scenario_capture_path"
  echo "visual_capture_path=$scenario_capture_path"
  rm -f "$capture_path"
}

verify_learning_flow_persistence() {
  if [[ "$VERIFY_SCENARIO" == "pi-course-memory-flow" ]]; then
    local workspace_file="$VERIFY_DATA_DIR/workspace.json"
    local marker_file="$VERIFY_DATA_DIR/pi-course-memory-verified.txt"
    for _ in {1..600}; do
      if [[ -s "$marker_file" ]] \
        && [[ -f "$workspace_file" ]] \
        && /usr/bin/grep -q '"learningMemoryEntries"' "$workspace_file" \
        && /usr/bin/grep -q '"studyLocationsByItemID"' "$workspace_file" \
        && /usr/bin/grep -q '"studySessions"' "$workspace_file" \
        && /usr/bin/grep -q '"confusion"' "$workspace_file" \
        && /usr/bin/grep -q '"userStatement"' "$workspace_file" \
        && /usr/bin/grep -q '"pi"' "$workspace_file"; then
        return 0
      fi
      sleep 0.2
    done
    echo "verify failed: packaged PI did not persist the course-memory learning flow." >&2
    if [[ -f "$VERIFY_DATA_DIR/verification-state.txt" ]]; then
      cat "$VERIFY_DATA_DIR/verification-state.txt" >&2
    fi
    [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
    return 1
  fi

  if [[ "$VERIFY_SCENARIO" == "pi-learning-flow" ]]; then
    local workspace_file="$VERIFY_DATA_DIR/workspace.json"
    local marker_file="$VERIFY_DATA_DIR/pi-agent-verified.txt"
    for _ in {1..600}; do
      if [[ -s "$marker_file" ]] \
        && [[ -f "$workspace_file" ]] \
        && /usr/bin/grep -q "视觉验收笔记" "$workspace_file" \
        && /usr/bin/grep -q "利率" "$workspace_file" \
        && ! /usr/bin/grep -q "## 离线草稿" "$workspace_file"; then
        return 0
      fi
      sleep 0.2
    done
    echo "verify failed: packaged PI did not complete the in-app learning flow." >&2
    if [[ -f "$VERIFY_DATA_DIR/verification-state.txt" ]]; then
      cat "$VERIFY_DATA_DIR/verification-state.txt" >&2
    fi
    return 1
  fi

  case "$VERIFY_SCENARIO" in
    offline-learning-flow|immersive-conversation-flow)
      ;;
    *)
      return 0
      ;;
  esac

  local workspace_file="$VERIFY_DATA_DIR/workspace.json"
  local workspace_notes=""
  for _ in {1..30}; do
    if [[ -f "$workspace_file" ]]; then
      workspace_notes="$(/usr/bin/plutil -extract notesByItemID json -o - "$workspace_file" 2>/dev/null || true)"
    fi
    if [[ -n "$workspace_notes" ]] \
      && /usr/bin/grep -q "## 整理建议" <<<"$workspace_notes" \
      && /usr/bin/grep -q "把可确认依据写入笔记" <<<"$workspace_notes" \
      && ! /usr/bin/grep -q "## 离线草稿" <<<"$workspace_notes" \
      && ! /usr/bin/grep -q "## 可确认" <<<"$workspace_notes"; then
      return 0
    fi
    sleep 0.2
  done

  echo "verify failed: offline learning flow did not persist a note-ready agent suggestion into workspace.json." >&2
  if [[ -f "$workspace_file" ]]; then
    /usr/bin/sed -n '1,80p' "$workspace_file" >&2
  else
    echo "missing workspace file: $workspace_file" >&2
  fi
  return 1
}

verify_empty_workspace_state() {
  case "$VERIFY_SCENARIO" in
    empty-workspace-*)
      ;;
    *)
      return 0
      ;;
  esac

  local workspace_file="$VERIFY_DATA_DIR/workspace.json"
  local expected_reader=false
  local expected_agent=false
  local expected_notes=false
  local expected_inspiration=true
  case "$VERIFY_SCENARIO" in
    empty-workspace-open-doc)
      expected_reader=true
      ;;
    empty-workspace-open-chat)
      expected_agent=true
      ;;
    empty-workspace-open-notes)
      expected_notes=true
      ;;
    empty-workspace-inspiration-off)
      expected_inspiration=false
      ;;
  esac

  for _ in {1..30}; do
    if [[ -f "$workspace_file" ]] \
      && /usr/bin/grep -q "\"showReader\":$expected_reader" "$workspace_file" \
      && /usr/bin/grep -q "\"showAgent\":$expected_agent" "$workspace_file" \
      && /usr/bin/grep -q "\"showNotes\":$expected_notes" "$workspace_file" \
      && /usr/bin/grep -q "\"showDailyInspiration\":$expected_inspiration" "$workspace_file"; then
      if [[ "$VERIFY_SCENARIO" == empty-workspace-open-* ]] \
        && ! /usr/bin/grep -q "Empty workspace entry state marker" "$workspace_file"; then
        sleep 0.2
        continue
      fi
      return 0
    fi
    sleep 0.2
  done

  echo "verify failed: empty-workspace pane or inspiration state was not persisted for $VERIFY_SCENARIO." >&2
  if [[ -f "$workspace_file" ]]; then
    /usr/bin/sed -n '1,80p' "$workspace_file" >&2
  else
    echo "missing workspace file: $workspace_file" >&2
  fi
  return 1
}

verify_linked_sources_flow() {
  if [[ "$VERIFY_SCENARIO" != "linked-sources-flow" ]]; then
    return 0
  fi

  local workspace_file="$VERIFY_DATA_DIR/workspace.json"
  for _ in {1..30}; do
    if [[ -f "$workspace_file" ]] \
      && /usr/bin/grep -q '"noteSourceLinks"' "$workspace_file" \
      && /usr/bin/grep -q '"sourceItemID":"sample-html"' "$workspace_file" \
      && /usr/bin/grep -q '"sourceItemID":"sample-pdf"' "$workspace_file" \
      && /usr/bin/grep -q '"selectedItemID":"sample-pdf"' "$workspace_file" \
      && /usr/bin/grep -q '"showLibrary":false' "$workspace_file" \
      && /usr/bin/grep -q '"activeNotebookItemID":"imported:' "$workspace_file" \
      && ! /usr/bin/grep -q '"activeNotebookItemID":"file:' "$workspace_file"; then
      return 0
    fi
    sleep 0.2
  done

  echo "verify failed: linked-sources-flow did not persist two sources while keeping the active note independent." >&2
  return 1
}

verify_course_workspace_flow() {
  local report_file=""
  case "$VERIFY_SCENARIO" in
    course-workspace-overview-flow)
      report_file="$VERIFY_DATA_DIR/course-workspace-overview-report.json"
      ;;
    course-workspace-workflow-flow)
      report_file="$VERIFY_DATA_DIR/course-workspace-workflow-report.json"
      ;;
    *)
      return 0
      ;;
  esac

  for _ in {1..150}; do
    if [[ -s "$report_file" ]]; then
      break
    fi
    sleep 0.2
  done
  if [[ ! -s "$report_file" ]]; then
    echo "verify failed: course workspace report was not produced for $VERIFY_SCENARIO." >&2
    [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
    return 1
  fi

  if [[ "$VERIFY_SCENARIO" == "course-workspace-overview-flow" ]]; then
    if ! /usr/bin/jq -e '
      .result == "pass"
      and .materialCount == 3
      and .noteCount == 3
      and .explicitLinkCount == 3
      and .readingPositionCount == 1
      and .studySessionCount == 1
      and .unresolvedConfusionCount == 1
      and .importClassificationPassed == true
      and .invalidNoteCreationPassed == true
      and .folderCountSummaryPassed == true
      and .unlinkedMaterialIDs == ["course-material-c"]
      and .unlinkedNoteIDs == ["course-note-c"]
      and .courseWorkspacePresented == true
    ' "$report_file" >/dev/null; then
      echo "verify failed: course workspace overview exposed inaccurate facts." >&2
      /usr/bin/jq . "$report_file" >&2
      return 1
    fi
  elif ! /usr/bin/jq -e '
    .result == "pass"
    and .continuityPassed == true
    and .importClassificationPassed == true
    and .invalidNoteCreationPassed == true
    and .folderCountSummaryPassed == true
    and .materialNavigationPassed == true
    and .noteNavigationPassed == true
    and .persistencePassed == true
    and .finalMaterialID == "course-material-c"
    and .finalNoteID == "course-note-c"
    and .noteA_sources == ["course-material-a"]
    and (.noteC_sources | sort) == ["course-material-b", "course-material-c"]
    and (.materialB_notes | sort) == ["course-note-b", "course-note-c"]
    and .paneMakeCount == 0
    and .paneDismantleCount == 0
  ' "$report_file" >/dev/null; then
    echo "verify failed: course workspace relationship workflow or pane continuity regressed." >&2
    /usr/bin/jq . "$report_file" >&2
    return 1
  fi

  /usr/bin/jq -r '"course_workspace_result=\(.result)"' "$report_file"
}

verify_pane_toggle_continuity() {
  if [[ "$VERIFY_SCENARIO" != "pane-toggle-continuity-flow" ]]; then
    return 0
  fi

  local report_file="$VERIFY_DATA_DIR/pane-toggle-continuity-report.txt"
  for _ in {1..1800}; do
    if [[ -f "$report_file" ]]; then
      if /usr/bin/grep -q '^result=pass$' "$report_file"; then
        verify_pane_trace_summary 480
        return $?
      fi
      echo "verify failed: pane toggles changed passive reading state or recreated a persistent pane." >&2
      cat "$report_file" >&2
      [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
      return 1
    fi
    sleep 0.2
  done

  echo "verify failed: pane-toggle continuity report was not produced." >&2
  [[ -f "$VERIFY_DATA_DIR/verification-state.txt" ]] && cat "$VERIFY_DATA_DIR/verification-state.txt" >&2
  [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
  return 1
}

verify_pane_trace_summary() {
  local minimum_transitions="$1"
  local summary_file="$VERIFY_DATA_DIR/pane-trace/summary.json"
  for _ in {1..100}; do
    if [[ -s "$summary_file" ]] \
      && /usr/bin/jq -e ".transitions >= $minimum_transitions" "$summary_file" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if [[ ! -s "$summary_file" ]]; then
    echo "verify failed: pane frame summary was not produced." >&2
    return 1
  fi
  if ! /usr/bin/jq -e ".transitions >= $minimum_transitions and .ownershipFailures == 0 and .blankVisibleFailures == 0 and .identityFailures == 0 and (.roleIdentities | length) == 3" "$summary_file" >/dev/null; then
    echo "verify failed: pane frame summary recorded unstable ownership or an empty visible slot." >&2
    /usr/bin/jq . "$summary_file" >&2
    return 1
  fi
  /usr/bin/jq -r '"pane_summary_samples=\(.samples)\npane_summary_transitions=\(.transitions)\npane_summary_failures=\(.ownershipFailures + .blankVisibleFailures + .identityFailures)"' "$summary_file"
}

verify_pane_layout_stability() {
  if [[ "$VERIFY_SCENARIO" != "pane-layout-stability-flow" ]]; then
    return 0
  fi

  local report_file="$VERIFY_DATA_DIR/pane-layout-stability-report.txt"
  local trace_dir="$VERIFY_DATA_DIR/pane-trace"
  for _ in {1..180}; do
    if [[ -f "$report_file" ]]; then
      if ! /usr/bin/grep -q '^result=pass$' "$report_file"; then
        echo "verify failed: pane state changed while exercising the stable workspace." >&2
        cat "$report_file" >&2
        [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
        return 1
      fi
      break
    fi
    sleep 0.2
  done

  if [[ ! -f "$report_file" ]]; then
    echo "verify failed: pane-layout stability report was not produced." >&2
    [[ -f "$VERIFY_DATA_DIR/verification-state.txt" ]] && cat "$VERIFY_DATA_DIR/verification-state.txt" >&2
    [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
    return 1
  fi

  local trace_files=()
  for _ in {1..50}; do
    shopt -s nullglob
    trace_files=("$trace_dir"/container-*.json)
    shopt -u nullglob
    (( ${#trace_files[@]} >= 120 )) && break
    sleep 0.1
  done
  if (( ${#trace_files[@]} < 120 )); then
    echo "verify failed: expected frame-level pane traces, found ${#trace_files[@]}." >&2
    return 1
  fi

  if ! /usr/bin/jq -s -e '
    def role_is_stable($role):
      ([.[] | .roles[] | select(.role == $role) | .hostID] | unique | length) == 1
      and ([.[] | .roles[] | select(.role == $role) | .parentID] | unique | length) == 1
      and ([.[] | .roles[] | select(.role == $role) | .contentHostID] | unique | length) == 1
      and ([.[] | .roles[] | select(.role == $role) | .contentParentID] | unique | length) == 1;
    ([.[].recorderID] | unique | length) == 1
    and ([.[].transition] | unique | length) >= 8
    and all(.[]; .stableOwnership == true and .noBlankVisibleSlots == true)
    and all((sort_by(.transition) | group_by(.transition))[]; length >= 15)
    and role_is_stable("reader")
    and role_is_stable("agent")
    and role_is_stable("notes")
  ' "${trace_files[@]}" >/dev/null; then
    echo "verify failed: a pane host changed identity/parent or exposed an empty visible slot during animation." >&2
    /usr/bin/jq -s '{samples:length, transitions:([.[].transition] | unique | length), ownership_failures:[.[] | select(.stableOwnership != true)] | length, blank_visible_failures:[.[] | select(.noBlankVisibleSlots != true)] | length}' "${trace_files[@]}" >&2
    return 1
  fi

  local transition_count
  transition_count="$(/usr/bin/jq -s '[.[].transition] | unique | length' "${trace_files[@]}")"
  echo "pane_trace_samples=${#trace_files[@]}"
  echo "pane_trace_transitions=$transition_count"
  echo "pane_host_and_parent_identity=stable"
  echo "pane_visible_slots=nonblank"
}

verify_pane_reorder_width() {
  if [[ "$VERIFY_SCENARIO" != "pane-reorder-width-flow" ]]; then
    return 0
  fi

  local report_file="$VERIFY_DATA_DIR/pane-reorder-width-report.txt"
  for _ in {1..180}; do
    if [[ -f "$report_file" ]]; then
      if ! /usr/bin/grep -q '^result=pass$' "$report_file"; then
        echo "verify failed: pane reorder, width restoration, or persistent state changed unexpectedly." >&2
        cat "$report_file" >&2
        [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
        return 1
      fi
      verify_pane_trace_summary 4
      return $?
    fi
    sleep 0.2
  done

  echo "verify failed: pane reorder and width report was not produced." >&2
  [[ -f "$VERIFY_DATA_DIR/verification-state.txt" ]] && cat "$VERIFY_DATA_DIR/verification-state.txt" >&2
  [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
  return 1
}

verify_reader_scroll_persistence() {
  if [[ "$VERIFY_SCENARIO" != "reader-scroll-persistence-flow" ]]; then
    return 0
  fi

  local report_file="$VERIFY_DATA_DIR/reader-scroll-persistence-report.txt"
  for _ in {1..120}; do
    if [[ -f "$report_file" ]]; then
      if /usr/bin/grep -q '^result=pass$' "$report_file"; then
        return 0
      fi
      echo "verify failed: user scroll did not persist and restore the HTML section." >&2
      cat "$report_file" >&2
      [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
      return 1
    fi
    sleep 0.2
  done

  echo "verify failed: reader scroll persistence report was not produced." >&2
  [[ -f "$VERIFY_DATA_DIR/verification-state.txt" ]] && cat "$VERIFY_DATA_DIR/verification-state.txt" >&2
  [[ -s "$VERIFY_STDERR" ]] && cat "$VERIFY_STDERR" >&2
  return 1
}

finish_verify_window() {
  verify_learning_flow_persistence
  verify_empty_workspace_state
  verify_linked_sources_flow
  verify_course_workspace_flow
  verify_pane_toggle_continuity
  verify_pane_layout_stability
  verify_pane_reorder_width
  verify_reader_scroll_persistence
  if [[ "$RUN_VISUAL_VERIFY" == true ]]; then
    visual_verify_window
  fi
}

run_verifiers() {
  WEIBEI_PI_EXECUTABLE="$PI_RUNTIME_BINARY" \
    swift run -c "$BUILD_CONFIGURATION" WeiBeiSelfCheck
  WEIBEI_SUPPRESS_ACTIVATION=1 \
    swift run -c "$BUILD_CONFIGURATION" WeiBei --self-check-imported-identity
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
  --verify|verify)
    run_verifiers
    open_app_for_verify
    for _ in {1..30}; do
      # Suppressed-activation runs may not register as onscreen even after the app-owned
      # capture proves the real window rendered. Accept either signal for visual checks.
      if verify_window >/dev/null 2>&1 \
        || { [[ "$RUN_VISUAL_VERIFY" == true ]] && [[ -s "$VERIFY_CAPTURE_PATH" ]]; }; then
        finish_verify_window
        exit 0
      fi
      sleep 0.2
    done
    verify_window
    finish_verify_window
    ;;
  --visual-verify|visual-verify)
    run_verifiers
    open_app_for_verify
    for _ in {1..30}; do
      # Suppressed-activation runs may not register as onscreen even after the app-owned
      # capture proves the real window rendered. Accept either signal for visual checks.
      if verify_window >/dev/null 2>&1 || [[ -s "$VERIFY_CAPTURE_PATH" ]]; then
        finish_verify_window
        exit $?
      fi
      sleep 0.2
    done
    verify_window
    finish_verify_window
    ;;
  *)
    echo "usage: $0 [run|check|package|--debug|--logs|--telemetry|--verify [--visual-verify]|--visual-verify]" >&2
    exit 2
    ;;
esac
