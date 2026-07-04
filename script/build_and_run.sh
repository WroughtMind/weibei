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
PRODUCT_NAME="WeiBei"
APP_DISPLAY_NAME="魏碑"
BUNDLE_ID="com.changfenhuang.weibei"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

if [[ "$CHECK_ONLY" == true ]]; then
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

swift build

if [[ "$CHECK_ONLY" != true ]]; then
  BUILD_DIR="$(swift build --show-bin-path)"
  BUILD_BINARY="$BUILD_DIR/$PRODUCT_NAME"
  RESOURCE_BUNDLE="$BUILD_DIR/${PRODUCT_NAME}_${PRODUCT_NAME}.bundle"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/"
    mkdir -p "$APP_CONTENTS/Resources"
    cp -R "$RESOURCE_BUNDLE" "$APP_CONTENTS/Resources/"
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
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_window() {
  swift -e 'import CoreGraphics; import Foundation; let owner = CommandLine.arguments[1]; func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }; let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []; let found = windows.contains { window in guard (window[kCGWindowOwnerName as String] as? String) == owner else { return false }; let bounds = window[kCGWindowBounds as String] as? [String: Any]; let isOnscreen = window[kCGWindowIsOnscreen as String] as? NSNumber; let visibleEnough = isOnscreen == nil || isOnscreen?.intValue != 0; return visibleEnough && number(window[kCGWindowLayer as String]) == 0 && number(bounds?["Width"]) >= 600 && number(bounds?["Height"]) >= 400 }; if !found { exit(1) }' "$APP_DISPLAY_NAME"
}

visual_verify_window() {
  local window_id
  window_id="$(swift -target arm64-apple-macosx14.0 -e 'import CoreGraphics; import Foundation; let owner = CommandLine.arguments[1]; func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }; let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []; guard let window = windows.first(where: { window in guard (window[kCGWindowOwnerName as String] as? String) == owner else { return false }; let bounds = window[kCGWindowBounds as String] as? [String: Any]; let isOnscreen = window[kCGWindowIsOnscreen as String] as? NSNumber; let visibleEnough = isOnscreen == nil || isOnscreen?.intValue != 0; return visibleEnough && number(window[kCGWindowLayer as String]) == 0 && number(bounds?["Width"]) >= 600 && number(bounds?["Height"]) >= 400 }), let id = window[kCGWindowNumber as String] as? UInt32 else { exit(1) }; print(id)' "$APP_DISPLAY_NAME")"
  local capture_path="${TMPDIR:-/tmp}/weibei-visual-verify-$window_id.png"
  local capture_error="${TMPDIR:-/tmp}/weibei-visual-verify-$window_id.err"
  if ! /usr/sbin/screencapture -x -l "$window_id" "$capture_path" 2>"$capture_error"; then
    cat "$capture_error" >&2
    echo "visual verify blocked: macOS refused window capture for $APP_DISPLAY_NAME. Grant Screen Recording permission to this terminal/Codex host, then rerun --visual-verify." >&2
    rm -f "$capture_path" "$capture_error"
    exit 5
  fi
  rm -f "$capture_error"
  swift -target arm64-apple-macosx14.0 -e 'import AppKit; import Foundation; let path = CommandLine.arguments[1]; guard let image = NSImage(contentsOf: URL(fileURLWithPath: path)), let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { exit(2) }; let xStep = max(1, bitmap.pixelsWide / 80); let yStep = max(1, bitmap.pixelsHigh / 60); var sampled = 0; var visible = 0; for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStep) { for x in stride(from: 0, to: bitmap.pixelsWide, by: xStep) { guard let color = bitmap.colorAt(x: x, y: y) else { continue }; if color.redComponent > 0.08 || color.greenComponent > 0.08 || color.blueComponent > 0.08 { visible += 1 }; sampled += 1 } }; guard sampled > 0 else { exit(3) }; let nonBlackRatio = Double(visible) / Double(sampled); print("visual_non_black_ratio=\(nonBlackRatio)"); if nonBlackRatio < 0.02 { fputs("visual verify failed: captured window is black or empty\n", stderr); exit(4) }' "$capture_path"
  rm -f "$capture_path"
}

run_verifiers() {
  swift run WeiBeiSelfCheck
  swift run WeiBeiWebEditorCheck
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
    open_app
    for _ in {1..30}; do
      if verify_window >/dev/null 2>&1; then
        if [[ "$RUN_VISUAL_VERIFY" == true ]]; then
          visual_verify_window
        fi
        exit 0
      fi
      sleep 0.2
    done
    verify_window
    if [[ "$RUN_VISUAL_VERIFY" == true ]]; then
      visual_verify_window
    fi
    ;;
  --visual-verify|visual-verify)
    run_verifiers
    open_app
    for _ in {1..30}; do
      if verify_window >/dev/null 2>&1; then
        visual_verify_window
        exit $?
      fi
      sleep 0.2
    done
    verify_window
    ;;
  *)
    echo "usage: $0 [run|check|package|--debug|--logs|--telemetry|--verify [--visual-verify]|--visual-verify]" >&2
    exit 2
    ;;
esac
