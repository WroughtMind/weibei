#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$ROOT/assets/app-icon/AppIcon.iconset"

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
TEMP_ICNS="$(mktemp "${TMPDIR:-/tmp}/weibei-app-icon.XXXXXX.icns")"
trap 'rm -f "$TEMP_ICNS"' EXIT
npm --prefix "$ROOT/.." exec -- tsx "$ROOT/scripts/build-icns.ts" "$ICON" "$TEMP_ICNS"
/usr/bin/cmp "$TEMP_ICNS" "$ROOT/assets/app-icon/AppIcon.icns"
npm --prefix "$ROOT/.." exec -- tsx "$ROOT/scripts/build-manifest.ts" "$ROOT" --check

echo "asset verification passed"
