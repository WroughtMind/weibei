#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
RUN_VISUAL_VERIFY=false
if [[ "$MODE" == "--visual-verify" || "$MODE" == "visual-verify" ]]; then
  MODE="--verify"
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
if [[ "$VERIFY_MODE" == true ]]; then
  DIST_DIR="${TMPDIR:-/tmp}/weibei-verify-$UID"
else
  DIST_DIR="$ROOT_DIR/dist"
fi
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
VERIFY_PID=""
VERIFY_DATA_DIR="$DIST_DIR/Data"
VERIFY_STDOUT="$VERIFY_DATA_DIR/app-stdout.log"
VERIFY_STDERR="$VERIFY_DATA_DIR/app-stderr.log"
VERIFY_SCENARIO="${WEIBEI_VERIFY_SCENARIO:-offline-learning-flow}"
VERIFY_WINDOW_SIZE="${WEIBEI_VERIFY_WINDOW_SIZE:-}"
VERIFY_INSPIRATION_ID="${WEIBEI_VERIFY_INSPIRATION_ID:-}"
VERIFY_CAPTURE_PATH="${TMPDIR:-/tmp}/weibei-self-capture-$UID-$VERIFY_SCENARIO.png"

if [[ "$CHECK_ONLY" == true ]]; then
  :
elif [[ "$VERIFY_MODE" == true ]]; then
  :
elif [[ "$PACKAGE_ONLY" == true ]]; then
  if pgrep -x "$PRODUCT_NAME" >/dev/null; then
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
fi

PI_RUNTIME_DIR="$("$ROOT_DIR/script/prepare_pi_runtime.sh")"
PI_RUNTIME_BINARY="$PI_RUNTIME_DIR/bin/pi"
PI_RUNTIME_VERSION="$(/usr/bin/plutil -extract piVersion raw -o - "$PI_RUNTIME_DIR/manifest.json")"
if [[ ! -x "$PI_RUNTIME_BINARY" ]]; then
  echo "build failed: embedded PI runtime was not prepared" >&2
  exit 8
fi

swift build -c "$BUILD_CONFIGURATION"

if [[ "$CHECK_ONLY" != true ]]; then
  BUILD_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
  BUILD_BINARY="$BUILD_DIR/$PRODUCT_NAME"
  RESOURCE_BUNDLES=(
    "$BUILD_DIR/${PRODUCT_NAME}_${PRODUCT_NAME}.bundle"
    "$BUILD_DIR/${PRODUCT_NAME}_WeiBeiCore.bundle"
  )

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$BUILD_BINARY" "$APP_BINARY"
  if ! /usr/bin/cmp -s "$BUILD_BINARY" "$APP_BINARY"; then
    echo "package failed: copied app binary does not match the current Swift build" >&2
    exit 10
  fi
  chmod +x "$APP_BINARY"
  for resource_bundle in "${RESOURCE_BUNDLES[@]}"; do
    if [[ ! -d "$resource_bundle" ]]; then
      echo "package failed: missing resource bundle $resource_bundle" >&2
      exit 7
    fi
    cp -R "$resource_bundle" "$APP_RESOURCES/"
  done
  cp -R "$PI_RUNTIME_DIR" "$APP_RESOURCES/PiRuntime"

  PACKAGED_PI="$APP_RESOURCES/PiRuntime/bin/pi"
  if [[ ! -x "$PACKAGED_PI" ]] \
    || [[ ! -f "$APP_RESOURCES/PiRuntime/manifest.json" ]] \
    || [[ ! -f "$APP_RESOURCES/PiRuntime/LICENSE" ]] \
    || [[ ! -f "$APP_RESOURCES/PiRuntime/THIRD_PARTY_NOTICES.md" ]] \
    || [[ ! -f "$APP_RESOURCES/PiRuntime/binary.sha256" ]] \
    || ! /usr/bin/codesign --verify --strict "$PACKAGED_PI" >/dev/null 2>&1 \
    || [[ "$(/usr/bin/shasum -a 256 "$PACKAGED_PI" | /usr/bin/awk '{print $1}')" != "$(<"$APP_RESOURCES/PiRuntime/binary.sha256")" ]] \
    || [[ "$("$PACKAGED_PI" --version 2>/dev/null)" != "$PI_RUNTIME_VERSION" ]]; then
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
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
  /usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  BUILD_UUID="$(/usr/bin/dwarfdump --uuid "$BUILD_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
  PACKAGED_UUID="$(/usr/bin/dwarfdump --uuid "$APP_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
  if [[ -z "$BUILD_UUID" || "$PACKAGED_UUID" != "$BUILD_UUID" ]]; then
    echo "package failed: signed app binary UUID does not match the current Swift build" >&2
    exit 11
  fi
  WEIBEI_PI_EXECUTABLE="$PACKAGED_PI" WEIBEI_PI_APP_BUNDLE="$APP_BUNDLE" WEIBEI_PI_LIVE_CHECK=0 \
    "$BUILD_DIR/WeiBeiPiCheck"
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
  if [[ "$VERIFY_SCENARIO" == "pi-learning-flow" || "$VERIFY_SCENARIO" == "pi-course-memory-flow" ]]; then
    agent_environment=(
      WEIBEI_FORCE_OFFLINE_AGENT=0
      WEIBEI_PI_PROVIDER=openai-codex
      WEIBEI_PI_MODEL=gpt-5.5
    )
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
    sleep 2.6
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
  swift -target arm64-apple-macosx14.0 -e 'import AppKit; import Foundation; let path = CommandLine.arguments[1]; guard let image = NSImage(contentsOf: URL(fileURLWithPath: path)), let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { exit(2) }; let xStep = max(1, bitmap.pixelsWide / 80); let yStep = max(1, bitmap.pixelsHigh / 60); var sampled = 0; var visible = 0; var black = 0; for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStep) { for x in stride(from: 0, to: bitmap.pixelsWide, by: xStep) { guard let color = bitmap.colorAt(x: x, y: y) else { continue }; if color.redComponent > 0.08 || color.greenComponent > 0.08 || color.blueComponent > 0.08 { visible += 1 }; if color.redComponent < 0.035 && color.greenComponent < 0.035 && color.blueComponent < 0.035 { black += 1 }; sampled += 1 } }; guard sampled > 0 else { exit(3) }; let nonBlackRatio = Double(visible) / Double(sampled); let blackRatio = Double(black) / Double(sampled); print("visual_non_black_ratio=\(nonBlackRatio)"); print("visual_black_ratio=\(blackRatio)"); if nonBlackRatio < 0.02 || blackRatio > 0.12 { fputs("visual verify failed: captured window is empty or contains black rendering blocks\n", stderr); exit(4) }' "$capture_path"
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
  for _ in {1..30}; do
    if [[ -f "$workspace_file" ]] \
      && /usr/bin/grep -q "## 整理建议" "$workspace_file" \
      && /usr/bin/grep -q "把可确认依据写入笔记" "$workspace_file" \
      && ! /usr/bin/grep -q "## 离线草稿" "$workspace_file" \
      && ! /usr/bin/grep -q "## 可确认" "$workspace_file"; then
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

finish_verify_window() {
  verify_learning_flow_persistence
  verify_empty_workspace_state
  if [[ "$RUN_VISUAL_VERIFY" == true ]]; then
    visual_verify_window
  fi
}

run_verifiers() {
  WEIBEI_PI_EXECUTABLE="$PI_RUNTIME_BINARY" \
    swift run -c "$BUILD_CONFIGURATION" WeiBeiSelfCheck
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
      if verify_window >/dev/null 2>&1; then
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
      if verify_window >/dev/null 2>&1; then
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
