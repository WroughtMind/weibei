#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/魏碑.app"
APP_BUNDLE_SET=false
REQUIRE_CLEAN=false

usage() {
  echo "usage: $0 [--require-clean] [path/to/魏碑.app]" >&2
}

while (( $# > 0 )); do
  case "$1" in
    --require-clean)
      REQUIRE_CLEAN=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -* )
      usage
      exit 2
      ;;
    *)
      if [[ "$APP_BUNDLE_SET" == true ]]; then
        usage
        exit 2
      fi
      APP_BUNDLE="$1"
      APP_BUNDLE_SET=true
      ;;
  esac
  shift
done

VERSION_FILE="$ROOT_DIR/VERSION"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/WeiBei"
APP_ICON="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
LEGAL_DIR="$APP_BUNDLE/Contents/Resources/Legal"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "metadata check failed: missing VERSION" >&2
  exit 3
fi
if [[ ! -f "$INFO_PLIST" || ! -x "$APP_BINARY" || ! -f "$APP_ICON" ]]; then
  echo "metadata check failed: incomplete app bundle at $APP_BUNDLE" >&2
  exit 4
fi
for legal_file in PRIVACY.md THIRD_PARTY_NOTICES.md ASSET_ATTRIBUTIONS.md v1.0.0.md; do
  if [[ ! -s "$LEGAL_DIR/$legal_file" ]]; then
    echo "metadata check failed: missing packaged notice $legal_file" >&2
    exit 10
  fi
done
if [[ "$(git -C "$ROOT_DIR" rev-parse --is-shallow-repository)" == "true" ]]; then
  echo "metadata check failed: full Git history is required for a stable build number" >&2
  exit 5
fi

EXPECTED_VERSION="$(/usr/bin/tr -d '\r\n' <"$VERSION_FILE")"
if [[ ! "$EXPECTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "metadata check failed: VERSION must use numeric major.minor.patch" >&2
  exit 6
fi

EXPECTED_COMMIT="$(git -C "$ROOT_DIR" rev-parse --verify HEAD)"
EXPECTED_BUILD="$(git -C "$ROOT_DIR" rev-list --count "$EXPECTED_COMMIT")"
EXPECTED_DIRTY=false
if [[ -n "$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=normal)" ]]; then
  EXPECTED_DIRTY=true
fi

if [[ "$REQUIRE_CLEAN" == true && "$EXPECTED_DIRTY" == true ]]; then
  echo "metadata check failed: a formal package must come from a clean worktree" >&2
  exit 7
fi

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
ACTUAL_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")"
ACTUAL_BUILD="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")"
ACTUAL_COMMIT="$(/usr/bin/plutil -extract WeiBeiGitCommit raw -o - "$INFO_PLIST")"
ACTUAL_DIRTY="$(/usr/bin/plutil -extract WeiBeiSourceDirty raw -o - "$INFO_PLIST")"
ACTUAL_BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")"
ACTUAL_ICON="$(/usr/bin/plutil -extract CFBundleIconFile raw -o - "$INFO_PLIST")"
ACTUAL_MIN_SYSTEM="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$INFO_PLIST")"

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "metadata check failed: $label expected $expected, got $actual" >&2
    exit 8
  fi
}

assert_equal "version" "$EXPECTED_VERSION" "$ACTUAL_VERSION"
assert_equal "build" "$EXPECTED_BUILD" "$ACTUAL_BUILD"
assert_equal "commit" "$EXPECTED_COMMIT" "$ACTUAL_COMMIT"
assert_equal "source dirty state" "$EXPECTED_DIRTY" "$ACTUAL_DIRTY"
assert_equal "bundle identifier" "com.changfenhuang.weibei" "$ACTUAL_BUNDLE_ID"
assert_equal "app icon" "AppIcon.icns" "$ACTUAL_ICON"
assert_equal "minimum system version" "14.0" "$ACTUAL_MIN_SYSTEM"

if [[ "$(/usr/bin/head -c 4 "$APP_ICON")" != "icns" ]]; then
  echo "metadata check failed: AppIcon.icns has an invalid header" >&2
  exit 9
fi

echo "release_metadata_version=$ACTUAL_VERSION"
echo "release_metadata_build=$ACTUAL_BUILD"
echo "release_metadata_commit=$ACTUAL_COMMIT"
echo "release_metadata_source_dirty=$ACTUAL_DIRTY"
echo "release_metadata_bundle_id=$ACTUAL_BUNDLE_ID"
echo "release_metadata_icon=$ACTUAL_ICON"
echo "release_metadata_min_system=$ACTUAL_MIN_SYSTEM"
echo "release_metadata_notices=packaged"
