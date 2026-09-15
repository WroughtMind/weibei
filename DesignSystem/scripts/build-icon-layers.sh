#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$ROOT/assets/app-icon/AppIcon.icon/Assets"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weibei-icon-layers.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$ASSETS"

# Derive both layers from the approved artwork so their placement never drifts.
convert "$ROOT/assets/logo/reference/approved-textured-mark-1254.png" \
  \( +clone -colorspace Gray -threshold 72% -negate \) \
  -alpha off -compose CopyOpacity -composite -strip "$TMP/full.png"
convert "$TMP/full.png" -filter Lanczos -resize 920x920 -background none -gravity center \
  -extent 1024x1024 "$TMP/mark.png"
convert "$TMP/mark.png" -channel A \
  -fx 'a*(r>1.5*g && r>1.5*b)' +channel -background none -alpha background -strip "$ASSETS/02-Cinnabar.png"
convert "$TMP/mark.png" -channel A \
  -fx 'a*!(r>1.5*g && r>1.5*b)' +channel "$TMP/ink.png"

# Close only tiny rubbing holes in the optical surface; their RGB grain remains.
# Otherwise the system bevels every transparent speck as a separate glass edge.
convert "$TMP/ink.png" -alpha extract -morphology Close Disk:2 \
  -fx 'u*(0.88+0.08*sin(2*pi*(0.8*i/w+0.35*j/h)))' "$TMP/ink-alpha.png"
convert "$TMP/ink.png" "$TMP/ink-alpha.png" -alpha off \
  -compose CopyOpacity -composite -strip "$ASSETS/01-Ink.png"
