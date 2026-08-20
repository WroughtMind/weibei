#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/Vendor/PiRuntime/manifest.json"
VERSION="$(/usr/bin/plutil -extract piVersion raw -o - "$MANIFEST")"
SOURCE_REPOSITORY="$(/usr/bin/plutil -extract sourceRepository raw -o - "$MANIFEST")"
HOST_ARCH="${WEIBEI_PI_ARCH:-$(uname -m)}"

case "$HOST_ARCH" in
  arm64)
    ARTIFACT_KEY="darwin-arm64"
    ;;
  x86_64)
    ARTIFACT_KEY="darwin-x64"
    ;;
  *)
    echo "embedded PI preparation failed: unsupported macOS architecture $HOST_ARCH" >&2
    exit 2
    ;;
esac

ARCHIVE_NAME="$(/usr/bin/plutil -extract "artifacts.$ARTIFACT_KEY.archive" raw -o - "$MANIFEST")"
EXPECTED_SHA256="$(/usr/bin/plutil -extract "artifacts.$ARTIFACT_KEY.sha256" raw -o - "$MANIFEST")"
CACHE_ROOT="${WEIBEI_PI_CACHE_DIR:-$ROOT_DIR/.build/pi-runtime}"
DOWNLOAD_DIR="$CACHE_ROOT/downloads"
RUNTIME_PARENT="$CACHE_ROOT/$VERSION/$ARTIFACT_KEY"
RUNTIME_DIR="$RUNTIME_PARENT/PiRuntime"
RUNTIME_BINARY="$RUNTIME_DIR/bin/pi"

runtime_is_ready() {
  [[ -x "$RUNTIME_BINARY" ]] \
    && [[ -f "$RUNTIME_DIR/bin/package.json" ]] \
    && [[ -f "$RUNTIME_DIR/bin/theme/dark.json" ]] \
    && [[ -f "$RUNTIME_DIR/bin/theme/light.json" ]] \
    && [[ -f "$RUNTIME_DIR/LICENSE" ]] \
    && [[ -f "$RUNTIME_DIR/THIRD_PARTY_NOTICES.md" ]] \
    && [[ -f "$RUNTIME_DIR/BUN_LICENSE.md" ]] \
    && [[ -f "$RUNTIME_DIR/LGPL-2.0.txt" ]] \
    && [[ -f "$RUNTIME_DIR/LGPL-2.1.txt" ]] \
    && [[ -f "$RUNTIME_DIR/RELINK.md" ]] \
    && [[ -f "$RUNTIME_DIR/binary.sha256" ]] \
    && cmp -s "$MANIFEST" "$RUNTIME_DIR/manifest.json" \
    && /usr/bin/codesign --verify --strict "$RUNTIME_BINARY" >/dev/null 2>&1 \
    && [[ "$(/usr/bin/shasum -a 256 "$RUNTIME_BINARY" | /usr/bin/awk '{print $1}')" == "$(<"$RUNTIME_DIR/binary.sha256")" ]] \
    && [[ "$("$RUNTIME_BINARY" --version 2>/dev/null)" == "$VERSION" ]]
}

if runtime_is_ready; then
  printf '%s\n' "$RUNTIME_DIR"
  exit 0
fi

mkdir -p "$DOWNLOAD_DIR" "$RUNTIME_PARENT"
LOCK_DIR="$CACHE_ROOT/.prepare-$ARTIFACT_KEY.lock"
LOCK_ACQUIRED=false
STAGING_DIR=""
cleanup() {
  if [[ -n "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR"
  fi
  if [[ "$LOCK_ACQUIRED" == true ]]; then
    rm -rf "$LOCK_DIR"
  fi
}
trap cleanup EXIT

for _ in {1..300}; do
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_ACQUIRED=true
    printf '%s\n' "$$" >"$LOCK_DIR/pid"
    break
  fi
  LOCK_MODIFIED="$(/usr/bin/stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)"
  if (( $(date +%s) - LOCK_MODIFIED > 600 )); then
    rm -rf "$LOCK_DIR"
    continue
  fi
  sleep 0.1
done
if [[ "$LOCK_ACQUIRED" != true ]]; then
  echo "embedded PI preparation failed: timed out waiting for runtime cache lock" >&2
  exit 6
fi

if runtime_is_ready; then
  printf '%s\n' "$RUNTIME_DIR"
  exit 0
fi

ARCHIVE_PATH="${WEIBEI_PI_ARCHIVE:-$DOWNLOAD_DIR/$ARCHIVE_NAME}"
if [[ ! -f "$ARCHIVE_PATH" ]]; then
  RELEASE_URL="$SOURCE_REPOSITORY/releases/download/v$VERSION/$ARCHIVE_NAME"
  echo "downloading embedded PI $VERSION for $HOST_ARCH" >&2
  /usr/bin/curl --fail --location --retry 3 --output "$DOWNLOAD_DIR/$ARCHIVE_NAME.part" "$RELEASE_URL"
  mv "$DOWNLOAD_DIR/$ARCHIVE_NAME.part" "$DOWNLOAD_DIR/$ARCHIVE_NAME"
  ARCHIVE_PATH="$DOWNLOAD_DIR/$ARCHIVE_NAME"
fi

ACTUAL_SHA256="$(/usr/bin/shasum -a 256 "$ARCHIVE_PATH" | /usr/bin/awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "embedded PI preparation failed: SHA-256 mismatch for $ARCHIVE_PATH" >&2
  exit 3
fi

STAGING_DIR="$RUNTIME_PARENT/.staging-$$"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/extracted" "$STAGING_DIR/PiRuntime/bin"
/usr/bin/tar -xzf "$ARCHIVE_PATH" -C "$STAGING_DIR/extracted"

SOURCE_DIR="$STAGING_DIR/extracted/pi"
for required in pi package.json theme/dark.json theme/light.json; do
  if [[ ! -e "$SOURCE_DIR/$required" ]]; then
    echo "embedded PI preparation failed: archive is missing $required" >&2
    exit 4
  fi
done

cp "$SOURCE_DIR/pi" "$STAGING_DIR/PiRuntime/bin/pi"
cp "$SOURCE_DIR/package.json" "$STAGING_DIR/PiRuntime/bin/package.json"
cp -R "$SOURCE_DIR/theme" "$STAGING_DIR/PiRuntime/bin/theme"
cp "$MANIFEST" "$STAGING_DIR/PiRuntime/manifest.json"
cp "$ROOT_DIR/Vendor/PiRuntime/LICENSE" "$STAGING_DIR/PiRuntime/LICENSE"
cp "$ROOT_DIR/Vendor/PiRuntime/THIRD_PARTY_NOTICES.md" "$STAGING_DIR/PiRuntime/THIRD_PARTY_NOTICES.md"
if [[ ! -f "$ROOT_DIR/Vendor/PiRuntime/BUN_LICENSE.md" ]]; then
  echo "embedded PI preparation failed: missing Vendor/PiRuntime/BUN_LICENSE.md" >&2
  exit 4
fi
cp "$ROOT_DIR/Vendor/PiRuntime/BUN_LICENSE.md" "$STAGING_DIR/PiRuntime/BUN_LICENSE.md"
cp "$ROOT_DIR/Vendor/PiRuntime/LGPL-2.0.txt" "$STAGING_DIR/PiRuntime/LGPL-2.0.txt"
cp "$ROOT_DIR/Vendor/PiRuntime/LGPL-2.1.txt" "$STAGING_DIR/PiRuntime/LGPL-2.1.txt"
cp "$ROOT_DIR/Vendor/PiRuntime/RELINK.md" "$STAGING_DIR/PiRuntime/RELINK.md"
printf '%s  %s\n' "$EXPECTED_SHA256" "$ARCHIVE_NAME" >"$STAGING_DIR/PiRuntime/artifact.sha256"
chmod 755 "$STAGING_DIR/PiRuntime/bin/pi"
/usr/bin/xattr -dr com.apple.quarantine "$STAGING_DIR/PiRuntime" 2>/dev/null || true
/usr/bin/codesign --force --sign - --timestamp=none "$STAGING_DIR/PiRuntime/bin/pi" >/dev/null
/usr/bin/codesign --verify --strict "$STAGING_DIR/PiRuntime/bin/pi"
/usr/bin/shasum -a 256 "$STAGING_DIR/PiRuntime/bin/pi" | /usr/bin/awk '{print $1}' >"$STAGING_DIR/PiRuntime/binary.sha256"

rm -rf "$RUNTIME_DIR"
mv "$STAGING_DIR/PiRuntime" "$RUNTIME_DIR"
if ! runtime_is_ready; then
  echo "embedded PI preparation failed: prepared runtime did not pass validation" >&2
  exit 5
fi

printf '%s\n' "$RUNTIME_DIR"
