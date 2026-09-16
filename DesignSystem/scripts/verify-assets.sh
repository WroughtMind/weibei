#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$ROOT/assets/app-icon/AppIcon.iconset"
ICON_COMPOSER="$ROOT/assets/app-icon/AppIcon.icon"

[[ -s "$ROOT/assets/fonts/WeiBeiStele.ttf" ]]
[[ -s "$ROOT/assets/fonts/WeiBeiSteleMono.ttf" ]]
if command -v fc-scan >/dev/null; then
  [[ "$(fc-scan --format '%{postscriptname}' "$ROOT/assets/fonts/WeiBeiStele.ttf")" == "WeiBeiStele-Regular" ]]
  [[ "$(fc-scan --format '%{postscriptname}' "$ROOT/assets/fonts/WeiBeiSteleMono.ttf")" == "WeiBeiSteleMono-Regular" ]]
fi

image_dimensions() {
  local file="$1"
  if command -v identify >/dev/null; then
    identify -format '%wx%h' "$file"
  else
    /usr/bin/sips -g pixelWidth -g pixelHeight "$file" 2>/dev/null \
      | /usr/bin/awk '/pixelWidth:/ { width=$2 } /pixelHeight:/ { height=$2 } END { print width "x" height }'
  fi
}

has_alpha() {
  local file="$1"
  if command -v identify >/dev/null; then
    [[ "$(identify -format '%[channels]' "$file")" == *a* ]]
  else
    [[ "$(/usr/bin/sips -g hasAlpha "$file" 2>/dev/null | /usr/bin/awk '/hasAlpha:/ { print $2 }')" == "yes" ]]
  fi
}

check_size() {
  local file="$1" expected="$2" actual
  actual="$(image_dimensions "$file")"
  [[ "$actual" == "${expected}x${expected}" ]] || {
    echo "size mismatch: $file is $actual, expected ${expected}x${expected}" >&2
    exit 1
  }
}

check_size "$ICON/icon_16x16.png" 16
check_size "$ICON/icon_16x16@2x.png" 32
check_size "$ICON/icon_32x32.png" 32
check_size "$ICON/icon_32x32@2x.png" 64
check_size "$ICON/icon_128x128.png" 128
check_size "$ICON/icon_128x128@2x.png" 256
check_size "$ICON/icon_256x256.png" 256
check_size "$ICON/icon_256x256@2x.png" 512
check_size "$ICON/icon_512x512.png" 512
check_size "$ICON/icon_512x512@2x.png" 1024
for layer in 01-Ink 02-Cinnabar; do
  check_size "$ICON_COMPOSER/Assets/$layer.png" 1024
  has_alpha "$ICON_COMPOSER/Assets/$layer.png"
done

# Check the visible contract: varying translucent ink, an opaque red anchor,
# and empty notches. This also catches accidental grayscale conversion.
swift - "$ICON_COMPOSER/Assets" <<'SWIFT_CHECK'
import AppKit
let assets = URL(fileURLWithPath: CommandLine.arguments[1])
func load(_ name: String) throws -> NSBitmapImageRep {
    let data = try Data(contentsOf: assets.appendingPathComponent(name))
    guard let image = NSBitmapImageRep(data: data) else { fatalError("Invalid image: \(name)") }
    return image
}
func pixel(_ image: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
        fatalError("Cannot read pixel at \(x), \(y)")
    }
    return color
}
let ink = try load("01-Ink.png"), cinnabar = try load("02-Cinnabar.png")
let alpha = [250, 500, 740].map { pixel(ink, $0, 400).alphaComponent }
precondition(alpha.allSatisfy { $0 > 0.79 && $0 < 0.97 }, "Ink must remain translucent")
precondition(alpha.max()! - alpha.min()! > 0.04, "Ink must vary in opacity")
let red = pixel(cinnabar, 840, 825)
precondition(red.alphaComponent > 0.99 && red.redComponent > 3 * red.greenComponent
    && red.redComponent > 3 * red.blueComponent, "Cinnabar must remain opaque and red")
precondition(pixel(ink, 840, 825).alphaComponent == 0)
precondition(pixel(cinnabar, 500, 400).alphaComponent == 0)
for (x, y) in [(398, 400), (630, 400), (50, 50)] {
    precondition(pixel(ink, x, y).alphaComponent == 0, "Ink notches must remain empty")
}
print("glass W alpha, cinnabar color, and notch checks passed")
SWIFT_CHECK
jq empty "$ICON_COMPOSER/icon.json"

COMPILED_ICON="$(mktemp -d "${TMPDIR:-/tmp}/weibei-icon-verify.XXXXXX")"
trap 'rm -rf "$COMPILED_ICON"' EXIT
xcrun actool \
  --compile "$COMPILED_ICON" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --target-device mac \
  --app-icon AppIcon \
  --output-partial-info-plist "$COMPILED_ICON/partial.plist" \
  --standalone-icon-behavior all \
  "$ICON_COMPOSER" >/dev/null
[[ "$(head -c 8 "$COMPILED_ICON/Assets.car")" == "BOMStore" ]]
[[ "$(head -c 4 "$COMPILED_ICON/AppIcon.icns")" == "icns" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$COMPILED_ICON/partial.plist")" == "AppIcon" ]]

[[ "$(head -c 4 "$ROOT/assets/app-icon/AppIcon.icns")" == "icns" ]] || {
  echo "invalid ICNS header" >&2
  exit 1
}

[[ "$(image_dimensions "$ROOT/assets/github/github-social-preview-1280x640.png")" == "1280x640" ]]
[[ "$(image_dimensions "$ROOT/assets/github/readme-hero-1983x793.png")" == "1983x793" ]]
has_alpha "$ROOT/assets/logo/exports/wordmark/weibei-wordmark-stamped.png"
(( $(wc -c <"$ROOT/assets/github/github-social-preview-1280x640.png") < 1048576 )) || {
  echo "GitHub social preview must remain below 1 MiB" >&2
  exit 1
}
has_alpha "$ROOT/assets/logo/exports/transparent/weibei-mark-flat-1024.png"
node --experimental-strip-types --check "$ROOT/scripts/build-icns.ts"
node --experimental-strip-types --check "$ROOT/scripts/build-manifest.ts"
node --test "$ROOT/scripts/build-manifest.test.mjs"
npx tsx "$ROOT/scripts/build-manifest.ts" "$ROOT" --check
python3 "$ROOT/../script/convert_editor_fonts.py" --check

echo "asset verification passed"
