#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="community"

usage() {
  echo "usage: $0 [--community|--notarized]" >&2
}

while (( $# > 0 )); do
  case "$1" in
    --community)
      MODE="community"
      ;;
    --notarized)
      MODE="notarized"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

VERSION_FILE="$ROOT_DIR/VERSION"
APP_NAME="魏碑.app"
BASE_APP="$ROOT_DIR/dist/$APP_NAME"
RELEASE_DIR="$ROOT_DIR/dist/release"
RELEASE_APP="$RELEASE_DIR/$APP_NAME"
PI_EXECUTABLE="$RELEASE_APP/Contents/Resources/PiRuntime/bin/pi"
PI_HASH="$RELEASE_APP/Contents/Resources/PiRuntime/binary.sha256"
PDF_HELPER="$RELEASE_APP/Contents/Helpers/WeiBeiPDFTextWorker"
BACKGROUND="$ROOT_DIR/DesignSystem/assets/dmg/dmg-background.png"
BACKGROUND_2X="$ROOT_DIR/DesignSystem/assets/dmg/dmg-background@2x.png"
PI_ENTITLEMENTS="$ROOT_DIR/Config/PiRuntime.entitlements"
NOTARY_RESULT="$RELEASE_DIR/notary-result.json"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "release failed: missing VERSION" >&2
  exit 3
fi
APP_VERSION="$(/usr/bin/tr -d '\r\n' <"$VERSION_FILE")"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "release failed: VERSION must use numeric major.minor.patch" >&2
  exit 4
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "release failed: the current package is intentionally Apple Silicon only" >&2
  exit 5
fi
PACKAGE_VERSION="$(node -p 'require(process.argv[1]).version' "$ROOT_DIR/package.json")"
if [[ "$PACKAGE_VERSION" != "$APP_VERSION" ]]; then
  echo "release failed: package.json version $PACKAGE_VERSION does not match VERSION $APP_VERSION" >&2
  exit 16
fi
if [[ -n "$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=normal)" ]]; then
  echo "release failed: package must come from a clean worktree" >&2
  exit 6
fi
if [[ ! -x "$ROOT_DIR/node_modules/.bin/appdmg" ]]; then
  echo "release failed: run npm ci before building the DMG" >&2
  exit 7
fi
for native_module in \
  "$ROOT_DIR/node_modules/macos-alias/build/Release/volume.node" \
  "$ROOT_DIR/node_modules/fs-xattr/build/Release/xattr.node"; do
  if [[ ! -f "$native_module" ]]; then
    echo "release failed: appdmg native modules are missing; run npm rebuild macos-alias fs-xattr" >&2
    exit 18
  fi
done

if [[ "$MODE" == "notarized" ]]; then
  SIGN_IDENTITY="${WEIBEI_CODESIGN_IDENTITY:-}"
  NOTARY_PROFILE="${WEIBEI_NOTARY_KEYCHAIN_PROFILE:-}"
  if [[ -z "$SIGN_IDENTITY" ]] \
    || ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$SIGN_IDENTITY\""; then
    echo "release failed: WEIBEI_CODESIGN_IDENTITY must name an installed Developer ID Application identity" >&2
    exit 8
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "release failed: WEIBEI_NOTARY_KEYCHAIN_PROFILE is required for notarization" >&2
    exit 9
  fi
  if [[ "${WEIBEI_NOTARIZED_RELEASE_APPROVED:-}" != "1" ]]; then
    echo "release failed: notarized publication requires WEIBEI_NOTARIZED_RELEASE_APPROVED=1" >&2
    exit 10
  fi
  if [[ "${WEIBEI_PI_REDISTRIBUTION_REVIEWED:-}" != "1" ]]; then
    echo "release failed: Pi/Bun redistribution review is not recorded" >&2
    exit 11
  fi
  TIMESTAMP_ARGUMENT=(--timestamp)
else
  SIGN_IDENTITY="-"
  NOTARY_PROFILE=""
  TIMESTAMP_ARGUMENT=(--timestamp=none)
fi

DMG_NAME="WeiBei-$APP_VERSION-macOS-arm64.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
DMG_SHA_PATH="$DMG_PATH.sha256"
CASK_PATH="$RELEASE_DIR/homebrew-tap/Casks/weibei.rb"

# Packaging never spends model quota or reads a live provider response.
export WEIBEI_PI_LIVE_CHECK=0

"$ROOT_DIR/DesignSystem/scripts/verify-assets.sh"
npm --prefix "$ROOT_DIR" ls --all >/dev/null

if [[ ! -s "$BACKGROUND" || ! -s "$BACKGROUND_2X" ]]; then
  swift "$ROOT_DIR/script/dmg/render_background.swift" "$ROOT_DIR/DesignSystem" "$BACKGROUND" 1
  swift "$ROOT_DIR/script/dmg/render_background.swift" "$ROOT_DIR/DesignSystem" "$BACKGROUND_2X" 2
fi

"$ROOT_DIR/script/build_and_run.sh" check
"$ROOT_DIR/script/build_and_run.sh" package
"$ROOT_DIR/script/verify_release_metadata.sh" --require-clean "$BASE_APP"

mkdir -p "$RELEASE_DIR"
rm -rf "$RELEASE_APP"
/usr/bin/ditto --norsrc --noextattr "$BASE_APP" "$RELEASE_APP"
/usr/bin/xattr -cr "$RELEASE_APP"

if [[ ! -x "$PI_EXECUTABLE" || ! -x "$PDF_HELPER" || ! -f "$PI_ENTITLEMENTS" ]]; then
  echo "release failed: packaged executables or Pi entitlements are missing" >&2
  exit 12
fi

/usr/bin/codesign --force --options runtime "${TIMESTAMP_ARGUMENT[@]}" \
  --entitlements "$PI_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$PI_EXECUTABLE"
/usr/bin/shasum -a 256 "$PI_EXECUTABLE" | /usr/bin/awk '{print $1}' | /usr/bin/tee "$PI_HASH" >/dev/null
/usr/bin/codesign --force --options runtime "${TIMESTAMP_ARGUMENT[@]}" \
  --sign "$SIGN_IDENTITY" "$PDF_HELPER"
/usr/bin/codesign --force --options runtime "${TIMESTAMP_ARGUMENT[@]}" \
  --sign "$SIGN_IDENTITY" "$RELEASE_APP"

/usr/bin/codesign --verify --strict --verbose=2 "$PI_EXECUTABLE"
/usr/bin/codesign --verify --strict --verbose=2 "$PDF_HELPER"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$RELEASE_APP"
"$ROOT_DIR/script/verify_release_metadata.sh" --require-clean "$RELEASE_APP"

BUILD_DIR="$(swift build -c release --show-bin-path)"
WEIBEI_PI_EXECUTABLE="$PI_EXECUTABLE" \
WEIBEI_PI_APP_BUNDLE="$RELEASE_APP" \
WEIBEI_PI_LIVE_CHECK=0 \
  "$BUILD_DIR/WeiBeiPiCheck"

npm --prefix "$ROOT_DIR" exec -- tsx "$ROOT_DIR/script/dmg/build_dmg.ts" "$ROOT_DIR" "$RELEASE_APP" "$DMG_PATH" "$APP_VERSION"

if [[ "$MODE" == "notarized" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  /usr/bin/codesign --verify --strict --verbose=2 "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json | /usr/bin/tee "$NOTARY_RESULT"
  NOTARY_STATUS="$(/usr/bin/plutil -extract status raw -o - "$NOTARY_RESULT")"
  if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    echo "release failed: Apple notarization returned $NOTARY_STATUS" >&2
    exit 13
  fi
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  /usr/sbin/spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
fi

/usr/bin/hdiutil verify "$DMG_PATH"

MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/weibei-dmg-verify.XXXXXX")"
VERIFY_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/weibei-dmg-data.XXXXXX")"
MOUNTED=false
detach_release_mount() {
  local attempt
  for attempt in {1..12}; do
    if /usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1; then
      MOUNTED=false
      return 0
    fi
    sleep 0.5
  done
  echo "release failed: mounted DMG remained busy after 12 detach attempts" >&2
  return 1
}
cleanup_mount() {
  if [[ "$MOUNTED" == true ]]; then
    detach_release_mount || /usr/bin/hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$MOUNT_DIR" "$VERIFY_DATA_DIR"
}
trap cleanup_mount EXIT

/usr/bin/hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -noautoopen -readonly >/dev/null
MOUNTED=true
if [[ ! -d "$MOUNT_DIR/$APP_NAME" || ! -L "$MOUNT_DIR/应用程序" ]]; then
  echo "release failed: mounted DMG is missing the app or Applications link" >&2
  exit 14
fi
/usr/bin/codesign --verify --deep --strict "$MOUNT_DIR/$APP_NAME"
MOUNTED_APP_BINARY="$MOUNT_DIR/$APP_NAME/Contents/MacOS/WeiBei"
MOUNTED_PI="$MOUNT_DIR/$APP_NAME/Contents/Resources/PiRuntime/bin/pi"
MOUNTED_PI_HASH="$MOUNT_DIR/$APP_NAME/Contents/Resources/PiRuntime/binary.sha256"
if ! /usr/bin/cmp -s \
  "$RELEASE_APP/Contents/MacOS/WeiBei" \
  "$MOUNTED_APP_BINARY"; then
  echo "release failed: mounted DMG app differs from the release app" >&2
  exit 15
fi
if [[ "$(/usr/bin/shasum -a 256 "$MOUNTED_PI" | /usr/bin/awk '{print $1}')" != "$(<"$MOUNTED_PI_HASH")" ]] \
  || [[ "$("$MOUNTED_PI" --version 2>/dev/null)" != "$(/usr/bin/plutil -extract piVersion raw -o - "$MOUNT_DIR/$APP_NAME/Contents/Resources/PiRuntime/manifest.json")" ]]; then
  echo "release failed: mounted DMG Pi runtime failed its hash or version check" >&2
  exit 17
fi
WEIBEI_SUPPRESS_ACTIVATION=1 \
WEIBEI_WORKSPACE_DIR="$VERIFY_DATA_DIR" \
  "$MOUNTED_APP_BINARY" --self-check-imported-identity
detach_release_mount

DMG_SHA256="$(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{print $1}')"
/usr/bin/printf '%s  %s\n' "$DMG_SHA256" "$DMG_NAME" | /usr/bin/tee "$DMG_SHA_PATH" >/dev/null
npm --prefix "$ROOT_DIR" exec -- tsx "$ROOT_DIR/script/homebrew/generate_cask.ts" "$APP_VERSION" "$DMG_SHA256" "$CASK_PATH"
/usr/bin/ruby -c "$CASK_PATH" >/dev/null

echo "release_mode=$MODE"
echo "release_app=$RELEASE_APP"
echo "release_dmg=$DMG_PATH"
echo "release_sha256=$DMG_SHA256"
echo "release_homebrew_cask=$CASK_PATH"
if [[ "$MODE" == "notarized" ]]; then
  echo "release_trust=notarized-developer-id"
else
  echo "release_trust=community-adhoc-unnotarized"
fi
