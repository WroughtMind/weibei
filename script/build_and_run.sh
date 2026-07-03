#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
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

pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true
for _ in {1..50}; do
  pgrep -x "$PRODUCT_NAME" >/dev/null || break
  sleep 0.1
done

if [[ -d "$ROOT_DIR/node_modules" ]]; then
  npm run build:editor >/dev/null
fi

swift build
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

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_window() {
  swift -e 'import CoreGraphics; import Foundation; let owner = CommandLine.arguments[1]; func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }; let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []; let found = windows.contains { window in guard (window[kCGWindowOwnerName as String] as? String) == owner else { return false }; let bounds = window[kCGWindowBounds as String] as? [String: Any]; return number(window[kCGWindowIsOnscreen as String]) == 1 && number(window[kCGWindowLayer as String]) == 0 && number(bounds?["Width"]) >= 600 && number(bounds?["Height"]) >= 400 }; if !found { exit(1) }' "$APP_DISPLAY_NAME"
}

case "$MODE" in
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
    open_app
    for _ in {1..30}; do
      if verify_window >/dev/null 2>&1; then
        exit 0
      fi
      sleep 0.2
    done
    verify_window
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
