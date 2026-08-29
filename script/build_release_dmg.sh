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
PDF_HELPER="$RELEASE_APP/Contents/Helpers/WeiBeiPDFTextWorker"
SPARKLE_FRAMEWORK="$RELEASE_APP/Contents/Frameworks/Sparkle.framework"
BACKGROUND="$ROOT_DIR/DesignSystem/assets/dmg/dmg-background.png"
BACKGROUND_2X="$ROOT_DIR/DesignSystem/assets/dmg/dmg-background@2x.png"
NOTARY_RESULT="$RELEASE_DIR/notary-result.json"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"
APPCAST_INPUT_DIR="$RELEASE_DIR/appcast-input"
SPARKLE_PUBLIC_KEY="${WEIBEI_SPARKLE_PUBLIC_KEY:-}"
SPARKLE_PRIVATE_KEY_FILE="${WEIBEI_SPARKLE_PRIVATE_KEY_FILE:-}"
SPARKLE_GENERATE_APPCAST="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
SPARKLE_SIGN_UPDATE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "release failed: missing VERSION" >&2
  exit 3
fi
APP_VERSION="$(/usr/bin/tr -d '\r\n' <"$VERSION_FILE")"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "release failed: VERSION must use numeric major.minor.patch" >&2
  exit 4
fi
UPDATE_SUMMARY_SOURCE="${WEIBEI_UPDATE_SUMMARY_FILE:-$ROOT_DIR/Docs/update-summaries/v$APP_VERSION.md}"
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
if [[ -n "$SPARKLE_PRIVATE_KEY_FILE" && -z "$SPARKLE_PUBLIC_KEY" ]]; then
  echo "release failed: WEIBEI_SPARKLE_PUBLIC_KEY is required when generating appcast.xml" >&2
  exit 18
fi
if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
  export WEIBEI_SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY"
fi

if [[ "$MODE" == "notarized" ]]; then
  SIGN_IDENTITY="${WEIBEI_CODESIGN_IDENTITY:-}"
  NOTARY_PROFILE="${WEIBEI_NOTARY_KEYCHAIN_PROFILE:-}"
  if [[ "$(/usr/bin/printf '%s' "$SPARKLE_PUBLIC_KEY" | /usr/bin/base64 -D 2>/dev/null | /usr/bin/wc -c | /usr/bin/tr -d ' ')" != "32" ]]; then
    echo "release failed: notarized publication requires a 32-byte base64 WEIBEI_SPARKLE_PUBLIC_KEY" >&2
    exit 18
  fi
  if [[ ! -s "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
    echo "release failed: notarized publication requires WEIBEI_SPARKLE_PRIVATE_KEY_FILE" >&2
    exit 21
  fi
  if [[ ! -x "$SPARKLE_GENERATE_APPCAST" || ! -x "$SPARKLE_SIGN_UPDATE" ]]; then
    echo "release failed: Sparkle generate_appcast and sign_update tools are missing" >&2
    exit 23
  fi
  SPARKLE_PUBLIC_VERIFIER="$(mktemp "${TMPDIR:-/tmp}/weibei-sparkle-public-key.XXXXXX")"
  trap '/bin/rm -f "$SPARKLE_PUBLIC_VERIFIER"' EXIT
  {
    /bin/dd if=/dev/zero bs=64 count=1 2>/dev/null
    /usr/bin/printf '%s' "$SPARKLE_PUBLIC_KEY" | /usr/bin/base64 -D
  } | /usr/bin/base64 -b 0 -o "$SPARKLE_PUBLIC_VERIFIER"
  if [[ "$(/usr/bin/base64 -D -i "$SPARKLE_PUBLIC_VERIFIER" | /usr/bin/wc -c | /usr/bin/tr -d ' ')" != "96" ]]; then
    /bin/rm -f "$SPARKLE_PUBLIC_VERIFIER"
    trap - EXIT
    echo "release failed: could not prepare the Sparkle public-key verifier" >&2
    exit 25
  fi
  if ! SPARKLE_PREFLIGHT_SIGNATURE="$(
    "$SPARKLE_SIGN_UPDATE" -p --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
      "$VERSION_FILE" 2>/dev/null
  )" || ! "$SPARKLE_SIGN_UPDATE" --verify --ed-key-file "$SPARKLE_PUBLIC_VERIFIER" \
    "$VERSION_FILE" "$SPARKLE_PREFLIGHT_SIGNATURE" >/dev/null 2>&1; then
    /bin/rm -f "$SPARKLE_PUBLIC_VERIFIER"
    trap - EXIT
    echo "release failed: WEIBEI_SPARKLE_PUBLIC_KEY does not match the Sparkle private key" >&2
    exit 25
  fi
  /bin/rm -f "$SPARKLE_PUBLIC_VERIFIER"
  trap - EXIT
  if [[ ! -s "$UPDATE_SUMMARY_SOURCE" ]]; then
    echo "release failed: notarized publication requires an in-app update summary" >&2
    exit 24
  fi
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

"$ROOT_DIR/DesignSystem/scripts/verify-assets.sh"
npm --prefix "$ROOT_DIR" ls --all >/dev/null

if [[ ! -s "$BACKGROUND" || ! -s "$BACKGROUND_2X" ]]; then
  swift "$ROOT_DIR/script/dmg/render_background.swift" "$ROOT_DIR/DesignSystem" "$BACKGROUND" 1
  swift "$ROOT_DIR/script/dmg/render_background.swift" "$ROOT_DIR/DesignSystem" "$BACKGROUND_2X" 2
fi

"$ROOT_DIR/script/build_and_run.sh" check
mkdir -p "$RELEASE_DIR"
"$ROOT_DIR/script/build_and_run.sh" package
(cd "$ROOT_DIR" && swift run --disable-keychain --disable-netrc WeiBeiDev verify-release-metadata --require-clean "$BASE_APP")

rm -rf "$RELEASE_APP"
/usr/bin/ditto --norsrc --noextattr "$BASE_APP" "$RELEASE_APP"
/usr/bin/xattr -cr "$RELEASE_APP"

BASE_BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BASE_APP/Contents/Info.plist")"
BASE_GIT_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :WeiBeiGitCommit' "$BASE_APP/Contents/Info.plist")"
BASE_DSYM_PATH="$ROOT_DIR/dist/WeiBei-$APP_VERSION-build-$BASE_BUILD_NUMBER-$BASE_GIT_COMMIT.dSYM"
DSYM_PATH="$RELEASE_DIR/$(basename "$BASE_DSYM_PATH")"
if [[ ! -d "$BASE_DSYM_PATH" || ! -s "$BASE_DSYM_PATH/Contents/Resources/DWARF/WeiBei" ]]; then
  echo "release failed: matching dSYM is missing from $BASE_DSYM_PATH" >&2
  exit 17
fi
/usr/bin/ditto --norsrc --noextattr "$BASE_DSYM_PATH" "$DSYM_PATH"
RELEASE_UUID="$(/usr/bin/dwarfdump --uuid "$RELEASE_APP/Contents/MacOS/WeiBei" | /usr/bin/awk 'NR == 1 {print $2}')"
DSYM_UUID="$(/usr/bin/dwarfdump --uuid "$DSYM_PATH" | /usr/bin/awk 'NR == 1 {print $2}')"
if [[ -z "$RELEASE_UUID" || "$DSYM_UUID" != "$RELEASE_UUID" ]]; then
  echo "release failed: dSYM UUID does not match the release app binary" >&2
  exit 30
fi

if [[ ! -x "$PDF_HELPER" || ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "release failed: packaged helper or Sparkle framework is missing" >&2
  exit 12
fi

/usr/bin/codesign --force --options runtime "${TIMESTAMP_ARGUMENT[@]}" \
  --sign "$SIGN_IDENTITY" "$PDF_HELPER"
/usr/bin/codesign --force --deep --options runtime "${TIMESTAMP_ARGUMENT[@]}" \
  --sign "$SIGN_IDENTITY" "$SPARKLE_FRAMEWORK"
/usr/bin/codesign --force --options runtime "${TIMESTAMP_ARGUMENT[@]}" \
  --sign "$SIGN_IDENTITY" "$RELEASE_APP"

/usr/bin/codesign --verify --strict --verbose=2 "$PDF_HELPER"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$SPARKLE_FRAMEWORK"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$RELEASE_APP"
(cd "$ROOT_DIR" && swift run --disable-keychain --disable-netrc WeiBeiDev verify-release-metadata --require-clean "$RELEASE_APP")
(cd "$ROOT_DIR" && swift run --disable-keychain --disable-netrc WeiBeiDev verify-production-hygiene "$RELEASE_APP")

npx tsx "$ROOT_DIR/script/dmg/build_dmg.ts" "$ROOT_DIR" "$RELEASE_APP" "$DMG_PATH" "$APP_VERSION"

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
  rm -rf "$MOUNT_DIR"
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
if ! /usr/bin/cmp -s \
  "$RELEASE_APP/Contents/MacOS/WeiBei" \
  "$MOUNTED_APP_BINARY"; then
  echo "release failed: mounted DMG app differs from the release app" >&2
  exit 15
fi
detach_release_mount

DMG_SHA256="$(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{print $1}')"
/usr/bin/printf '%s  %s\n' "$DMG_SHA256" "$DMG_NAME" | /usr/bin/tee "$DMG_SHA_PATH" >/dev/null
npx tsx "$ROOT_DIR/script/homebrew/generate_cask.ts" "$APP_VERSION" "$DMG_SHA256" "$CASK_PATH"
/usr/bin/ruby -c "$CASK_PATH" >/dev/null

APPCAST_RESULT="not-generated"
if [[ "$MODE" == "notarized" || -n "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" || ! -s "$UPDATE_SUMMARY_SOURCE" ]]; then
    echo "release failed: Sparkle private key or in-app update summary is missing" >&2
    exit 21
  fi
  rm -rf "$APPCAST_INPUT_DIR"
  mkdir -p "$APPCAST_INPUT_DIR"
  /usr/bin/ditto --norsrc --noextattr "$DMG_PATH" "$APPCAST_INPUT_DIR/$DMG_NAME"
  cp "$UPDATE_SUMMARY_SOURCE" "$APPCAST_INPUT_DIR/${DMG_NAME%.dmg}.md"
  "$SPARKLE_GENERATE_APPCAST" \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    --download-url-prefix "https://github.com/weibei-app/weibei/releases/download/v$APP_VERSION/" \
    --embed-release-notes \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    -o "$APPCAST_PATH" \
    "$APPCAST_INPUT_DIR"
  "$SPARKLE_SIGN_UPDATE" --verify --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$APPCAST_PATH"
  APPCAST_RESULT="$APPCAST_PATH"
fi

echo "release_mode=$MODE"
echo "release_app=$RELEASE_APP"
echo "release_dmg=$DMG_PATH"
echo "release_sha256=$DMG_SHA256"
echo "release_homebrew_cask=$CASK_PATH"
echo "release_appcast=$APPCAST_RESULT"
if [[ "$MODE" == "notarized" ]]; then
  echo "release_trust=notarized-developer-id"
else
  echo "release_trust=community-adhoc-unnotarized"
fi
