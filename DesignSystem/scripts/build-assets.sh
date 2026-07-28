#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REFERENCE="$ROOT/assets/logo/reference/approved-textured-mark-1254.png"
HERO_ORIGINAL="$ROOT/assets/github/readme-hero-original-1983x793.png"
HERO_CORRECTED="$ROOT/assets/github/readme-hero-1983x793.png"
FONT_STELE="$ROOT/assets/fonts/WeiBeiStele.ttf"
FONT_MONO="$ROOT/assets/fonts/WeiBeiSteleMono.ttf"
LOGO="$ROOT/assets/logo"
ICON="$ROOT/assets/app-icon"
WEB="$ROOT/assets/web"
GITHUB="$ROOT/assets/github"
SOCIAL="$ROOT/assets/social"
TMP="${TMPDIR:-/tmp}/weibei-brand-assets-$$"

command -v convert >/dev/null || { echo "ImageMagick 'convert' is required" >&2; exit 1; }
[[ -f "$REFERENCE" ]] || { echo "Missing $REFERENCE" >&2; exit 2; }
[[ -f "$HERO_ORIGINAL" ]] || { echo "Missing $HERO_ORIGINAL" >&2; exit 2; }
[[ -f "$FONT_STELE" ]] || { echo "Missing $FONT_STELE" >&2; exit 2; }
[[ -f "$FONT_MONO" ]] || { echo "Missing $FONT_MONO" >&2; exit 2; }

mkdir -p "$TMP" "$LOGO/exports/paper" "$LOGO/exports/transparent" \
  "$LOGO/exports/monochrome" "$LOGO/exports/reversed" \
  "$ICON/AppIcon.iconset" "$ICON/AppIcon.appiconset" "$ICON/previews" \
  "$WEB" "$GITHUB" "$SOCIAL" "$ROOT/assets/swatches" "$ROOT/assets/examples"
trap 'rm -rf "$TMP"' EXIT

# Lock the generated visual reference, then derive deterministic exports from it.
convert "$REFERENCE" -strip -colorspace sRGB "$LOGO/exports/paper/weibei-mark-paper-1254.png"
convert "$REFERENCE" -filter Lanczos -resize 1024x1024 -strip -colorspace sRGB \
  "$LOGO/exports/paper/weibei-mark-paper-1024.png"

# Textured transparent version: remove paper by luminance while retaining rubbing voids.
convert "$REFERENCE" \
  \( +clone -colorspace Gray -threshold 72% -negate \) \
  -alpha off -compose CopyOpacity -composite -strip \
  "$TMP/weibei-mark-textured-transparent.png"
cp "$TMP/weibei-mark-textured-transparent.png" \
  "$LOGO/exports/transparent/weibei-mark-textured-transparent.png"

# Stable clean versions come from the same normalized geometry as the SVG.
# Drawing locally keeps the export pipeline independent from an SVG renderer.
MARK_PATH="M220,170 L432,170 L432,708 L158,708 L158,260 Z \
M511,170 L749,170 L749,708 L511,708 Z \
M825,170 L1010,170 L1098,258 L1098,708 L825,708 Z \
M158,708 L432,708 L474,816 L511,708 L749,708 L789,816 L825,708 L1098,708 \
L1098,940 L1014,1025 L982,1083 L915,1083 L814,967 L720,1083 L585,1083 \
L482,967 L391,1083 L270,1083 L158,960 Z"
convert -size 1254x1254 xc:none -fill '#231F1C' -draw "path '$MARK_PATH'" \
  -fill '#AA2A23' -draw 'rectangle 1042,1020 1108,1086' "$TMP/flat-color-1254.png"
convert -size 1254x1254 xc:none -fill '#231F1C' -draw "path '$MARK_PATH'" \
  -fill '#231F1C' -draw 'rectangle 1042,1020 1108,1086' "$TMP/flat-black-1254.png"
convert -size 1254x1254 xc:none -fill '#F7F0E4' -draw "path '$MARK_PATH'" \
  -fill '#D66A58' -draw 'rectangle 1042,1020 1108,1086' "$TMP/flat-reversed-1254.png"
convert -size 1254x1254 xc:none -fill white -draw "path '$MARK_PATH'" \
  -fill white -draw 'rectangle 1042,1020 1108,1086' "$TMP/flat-white-1254.png"
convert "$TMP/flat-color-1254.png" -filter Lanczos -resize 1024x1024 \
  "$LOGO/exports/transparent/weibei-mark-flat-1024.png"
convert "$TMP/flat-black-1254.png" -filter Lanczos -resize 1024x1024 \
  "$LOGO/exports/monochrome/weibei-mark-black-1024.png"
convert "$TMP/flat-reversed-1254.png" -filter Lanczos -resize 1024x1024 \
  "$LOGO/exports/reversed/weibei-mark-reversed-1024.png"
convert "$TMP/flat-white-1254.png" -filter Lanczos -resize 1024x1024 \
  "$LOGO/exports/monochrome/weibei-mark-white-1024.png"

for size in 128 256 512; do
  convert "$LOGO/exports/transparent/weibei-mark-flat-1024.png" -filter Lanczos -resize "${size}x${size}" \
    "$LOGO/exports/transparent/weibei-mark-flat-${size}.png"
done

# Brand typography must use the repository's own fonts, not a look-alike fallback.
convert -background none -fill '#231F1C' -font "$FONT_STELE" -pointsize 250 -kerning 18 \
  label:WEIBEI "$LOGO/exports/wordmark/weibei-wordmark-stamped.png"
convert -background none -fill '#686157' -font "$FONT_MONO" -pointsize 54 -kerning 7 \
  'label:READ · NOTE · ASK · RETURN TO SOURCE' "$LOGO/exports/wordmark/weibei-tagline-mono.png"
convert "$LOGO/exports/transparent/weibei-mark-flat-1024.png" -resize 520x520 "$TMP/lockup-mark.png"
convert "$LOGO/exports/wordmark/weibei-wordmark-stamped.png" -resize 920x230 "$TMP/lockup-wordmark.png"
convert "$LOGO/exports/wordmark/weibei-tagline-mono.png" -resize 1080x76 "$TMP/lockup-tagline.png"
convert -size 1940x620 xc:none "$TMP/lockup-mark.png" -geometry +24+50 -composite \
  "$TMP/lockup-wordmark.png" -geometry +680+165 -composite \
  "$TMP/lockup-tagline.png" -geometry +690+430 -composite \
  "$LOGO/exports/wordmark/weibei-lockup-en.png"

# Build a textured macOS icon master with transparent outer corners.
convert "$REFERENCE" -filter Lanczos -resize 920x920! "$TMP/icon-content.png"
convert -size 920x920 xc:none -fill white -draw 'roundrectangle 0,0 919,919 184,184' "$TMP/icon-mask.png"
convert "$TMP/icon-content.png" "$TMP/icon-mask.png" -alpha on -channel A -fx 'v' +channel \
  -bordercolor none -border 52 -strip "$ICON/weibei-app-icon-1024.png"

# Small-size optical master: flat ink, calmer paper, deliberately enlarged cinnabar anchor.
convert -size 1254x1254 xc:none -fill '#231F1C' -draw "path '$MARK_PATH'" \
  -fill '#AA2A23' -draw 'rectangle 1040,1006 1134,1100' -filter Lanczos -resize 920x920 \
  "$TMP/small-mark.png"
convert -size 920x920 xc:none -fill '#F2E2CA' -draw 'roundrectangle 0,0 919,919 184,184' \
  "$TMP/small-paper.png"
convert "$TMP/small-paper.png" "$TMP/small-mark.png" -compose over -composite \
  -bordercolor none -border 52 -strip "$ICON/weibei-app-icon-small-optical-1024.png"

make_icon() {
  local pixels="$1" output="$2" source="$ICON/weibei-app-icon-1024.png"
  if (( pixels <= 64 )); then source="$ICON/weibei-app-icon-small-optical-1024.png"; fi
  convert "$source" -filter Lanczos -resize "${pixels}x${pixels}" -strip "$output"
}

make_icon 16   "$ICON/AppIcon.iconset/icon_16x16.png"
make_icon 32   "$ICON/AppIcon.iconset/icon_16x16@2x.png"
make_icon 32   "$ICON/AppIcon.iconset/icon_32x32.png"
make_icon 64   "$ICON/AppIcon.iconset/icon_32x32@2x.png"
make_icon 128  "$ICON/AppIcon.iconset/icon_128x128.png"
make_icon 256  "$ICON/AppIcon.iconset/icon_128x128@2x.png"
make_icon 256  "$ICON/AppIcon.iconset/icon_256x256.png"
make_icon 512  "$ICON/AppIcon.iconset/icon_256x256@2x.png"
make_icon 512  "$ICON/AppIcon.iconset/icon_512x512.png"
make_icon 1024 "$ICON/AppIcon.iconset/icon_512x512@2x.png"

cp "$ICON/AppIcon.iconset/"*.png "$ICON/AppIcon.appiconset/"

# Web and social exports use the optical master at tiny sizes.
for size in 16 32 48 180 192 512; do
  make_icon "$size" "$WEB/icon-${size}.png"
done
cp "$WEB/icon-180.png" "$WEB/apple-touch-icon-180.png"
cp "$WEB/icon-192.png" "$WEB/web-app-icon-192.png"
cp "$WEB/icon-512.png" "$WEB/web-app-icon-512.png"
convert "$WEB/icon-16.png" "$WEB/icon-32.png" "$WEB/icon-48.png" "$WEB/favicon.ico"

make_icon 512 "$GITHUB/github-avatar-512.png"
convert "$LOGO/exports/transparent/weibei-mark-textured-transparent.png" -filter Lanczos -resize 256x256 \
  "$GITHUB/readme-logo-256.png"
convert "$LOGO/exports/transparent/weibei-mark-textured-transparent.png" -filter Lanczos -resize 512x512 \
  "$GITHUB/readme-logo-512.png"

# Locked paper texture for brand surfaces only; mirrored tiling prevents hard seams.
convert "$REFERENCE" -crop 180x150+0+0 +repage \
  \( +clone -flop \) +append \( +clone -flip \) -append "$TMP/paper-tile.png"
convert -size 2048x2048 tile:"$TMP/paper-tile.png" -strip "$LOGO/source/paper-texture-2048.png"

# Preserve the approved hero composition while replacing the generated Latin wordmark
# with the real WeiBeiStele font from the repository.
convert "$HERO_ORIGINAL" -crop 430x92+0+0 +repage -resize 430x92! "$TMP/hero-wordmark-paper.png"
convert -background none -fill '#231F1C' -font "$FONT_STELE" -pointsize 58 -kerning 20 \
  label:WEIBEI "$TMP/hero-wordmark.png"
convert "$HERO_ORIGINAL" "$TMP/hero-wordmark-paper.png" -geometry +84+416 -composite \
  "$TMP/hero-wordmark.png" -geometry +118+433 -composite -strip "$HERO_CORRECTED"

# GitHub social preview: preserve the existing paper/diagram language and reveal the full mark.
convert "$LOGO/source/paper-texture-2048.png" -gravity center -crop 1280x640+0+0 +repage "$TMP/social-paper.png"
convert "$HERO_CORRECTED" -crop 1030x793+0+0 +repage -filter Lanczos -resize 790x608 "$TMP/social-left.png"
convert "$LOGO/exports/transparent/weibei-mark-textured-transparent.png" -filter Lanczos -resize 470x470 "$TMP/social-mark.png"
convert "$TMP/social-paper.png" "$TMP/social-left.png" -geometry +16+16 -composite \
  "$TMP/social-mark.png" -geometry +790+78 -composite -strip \
  "$TMP/github-social-preview-1280x640.png"
cp "$TMP/github-social-preview-1280x640.png" "$GITHUB/github-social-preview-1280x640.png"

convert "$REFERENCE" -filter Lanczos -resize 1080x1080 -strip "$SOCIAL/weibei-square-1080.png"
convert "$TMP/github-social-preview-1280x640.png" -filter Lanczos -resize 1200x600 \
  -background '#F2E2CA' -gravity center -extent 1200x630 -strip "$SOCIAL/weibei-og-1200x630.png"

# Visual review sheets.
convert "$ICON/weibei-app-icon-1024.png" -background '#ECE8E1' -gravity center -extent 1180x1180 \
  -resize 520x520 "$TMP/icon-light.png"
convert "$ICON/weibei-app-icon-1024.png" -background '#1D1C1A' -gravity center -extent 1180x1180 \
  -resize 520x520 "$TMP/icon-dark.png"
convert "$TMP/icon-light.png" "$TMP/icon-dark.png" +append "$ICON/previews/app-icon-light-dark.png"

convert "$ICON/AppIcon.iconset/icon_16x16.png" -filter point -resize 256x256 "$TMP/icon-16-review.png"
convert "$ICON/AppIcon.iconset/icon_32x32.png" -filter point -resize 256x256 "$TMP/icon-32-review.png"
convert "$ICON/AppIcon.iconset/icon_32x32@2x.png" -filter point -resize 256x256 "$TMP/icon-64-review.png"
convert "$ICON/AppIcon.iconset/icon_128x128.png" -filter point -resize 256x256 "$TMP/icon-128-review.png"
convert "$TMP/icon-16-review.png" "$TMP/icon-32-review.png" "$TMP/icon-64-review.png" "$TMP/icon-128-review.png" \
  +append "$ICON/previews/app-icon-small-size-test.png"

convert -size 1200x420 xc:'#F7F0E4' \
  -fill '#F2E2CA' -draw 'rectangle 0,0 149,419' \
  -fill '#F7F0E4' -draw 'rectangle 150,0 299,419' \
  -fill '#231F1C' -draw 'rectangle 300,0 449,419' \
  -fill '#34312C' -draw 'rectangle 450,0 599,419' \
  -fill '#686157' -draw 'rectangle 600,0 749,419' \
  -fill '#D5C7B3' -draw 'rectangle 750,0 899,419' \
  -fill '#4D667A' -draw 'rectangle 900,0 1049,419' \
  -fill '#AA2A23' -draw 'rectangle 1050,0 1199,419' \
  "$ROOT/assets/swatches/core-palette.png"

convert -size 1600x900 xc:'#F2E2CA' \
  -fill '#231F1C' -font "$FONT_STELE" -pointsize 250 -kerning 18 -gravity northwest \
  -annotate +120+90 'WEIBEI' \
  -fill '#55493E' -font "$FONT_STELE" -pointsize 76 -kerning 8 \
  -annotate +128+390 'READ  NOTE  ASK' \
  -fill '#305469' -font "$FONT_MONO" -pointsize 48 -kerning 4 \
  -annotate +128+560 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' \
  -fill '#686157' -pointsize 42 -kerning 3 \
  -annotate +128+680 '0123456789  —  SOURCE: PAGE 12' \
  "$ROOT/assets/fonts/previews/weibei-font-specimen.png"

convert "$LOGO/exports/paper/weibei-mark-paper-1024.png" -resize 380x380 "$TMP/variant-paper.png"
convert -size 420x420 xc:'#F7F0E4' "$LOGO/exports/transparent/weibei-mark-flat-1024.png" \
  -resize 340x340 -gravity center -composite "$TMP/variant-flat.png"
convert -size 420x420 xc:'#1D1C1A' "$LOGO/exports/reversed/weibei-mark-reversed-1024.png" \
  -resize 340x340 -gravity center -composite "$TMP/variant-reversed.png"
convert -size 420x420 xc:white "$LOGO/exports/monochrome/weibei-mark-black-1024.png" \
  -resize 340x340 -gravity center -composite "$TMP/variant-mono.png"
convert "$TMP/variant-paper.png" -gravity center -background '#F4EAD5' -extent 420x420 \
  "$TMP/variant-flat.png" "$TMP/variant-reversed.png" "$TMP/variant-mono.png" +append \
  "$ROOT/assets/examples/logo-variants.png"

convert "$LOGO/exports/paper/weibei-mark-paper-1024.png" -resize 420x420 "$TMP/board-logo.png"
convert "$ICON/weibei-app-icon-1024.png" -resize 360x360 "$TMP/board-icon.png"
convert "$LOGO/exports/reversed/weibei-mark-reversed-1024.png" -resize 340x340 \
  -background '#1D1C1A' -gravity center -extent 420x420 "$TMP/board-reversed.png"
convert "$TMP/github-social-preview-1280x640.png" -resize 760x380 "$TMP/board-social.png"
convert "$ROOT/assets/swatches/core-palette.png" -resize 700x245 "$TMP/board-palette.png"
convert -size 1600x900 xc:'#F4EAD5' "$TMP/board-logo.png" -geometry +40+40 -composite \
  "$TMP/board-icon.png" -geometry +500+70 -composite \
  "$TMP/board-reversed.png" -geometry +900+40 -composite \
  "$TMP/board-social.png" -geometry +40+490 -composite \
  "$TMP/board-palette.png" -geometry +860+565 -composite \
  "$ROOT/assets/examples/design-system-overview.png"

npm --prefix "$ROOT/.." exec -- tsx "$ROOT/scripts/build-icns.ts" "$ICON/AppIcon.iconset" "$ICON/AppIcon.icns"
npm --prefix "$ROOT/.." exec -- tsx "$ROOT/scripts/build-manifest.ts" "$ROOT"

echo "WeiBei design assets rebuilt at $ROOT/assets"
