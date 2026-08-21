#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUTS="$ROOT_DIR/Vendor/PiRuntime/license-review-inputs.json"
LOCK="$ROOT_DIR/Vendor/PiRuntime/relink-bundle.lock.json"
MODE="${1:---prepare}"
BUNDLE_ARGUMENT="${2:-}"
CACHE_ROOT="${WEIBEI_PI_RELINK_CACHE_DIR:-$ROOT_DIR/.build/pi-runtime-relink}"
DOWNLOAD_DIR="$CACHE_ROOT/downloads"

if [[ ! -d "$ROOT_DIR/node_modules/tsx" ]]; then
  echo "Pi relink bundle failed: run npm ci first" >&2
  exit 2
fi

FINGERPRINT="$(cd "$ROOT_DIR" && node --import tsx script/check_pi_runtime_license_report.ts --fingerprint)"
BUNDLE_ID="WeiBei-Pi-relink-$FINGERPRINT"
BUNDLE_NAME="$BUNDLE_ID.tar.gz"
BUNDLE_PATH="$CACHE_ROOT/$BUNDLE_NAME"

json_value() {
  node -e 'const v=process.argv[1].split(".").reduce((o,k)=>o[k],JSON.parse(require("fs").readFileSync(process.argv[2],"utf8"))); process.stdout.write(String(v))' "$1" "$INPUTS"
}

verify_bundle() {
  local bundle="$1" actual_sha expected_sha locked_fingerprint archived_fingerprint
  if [[ ! -f "$bundle" || ! -f "$LOCK" ]]; then
    echo "Pi relink bundle failed: bundle or relink-bundle.lock.json is missing" >&2
    return 1
  fi
  expected_sha="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).sha256)' "$LOCK")"
  locked_fingerprint="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).fingerprint)' "$LOCK")"
  [[ "$locked_fingerprint" == "$FINGERPRINT" ]] || {
    echo "Pi relink bundle failed: source pins changed; regenerate the one-time bundle" >&2
    return 1
  }
  actual_sha="$(/usr/bin/shasum -a 256 "$bundle" | /usr/bin/awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || {
    echo "Pi relink bundle failed: bundle SHA-256 mismatch" >&2
    return 1
  }
  archived_fingerprint="$(/usr/bin/tar -xOf "$bundle" "$BUNDLE_ID/bundle-fingerprint.txt")"
  [[ "$archived_fingerprint" == "$FINGERPRINT" ]] || {
    echo "Pi relink bundle failed: archived fingerprint mismatch" >&2
    return 1
  }
  printf '%s\n' "$bundle"
}

if [[ "$MODE" == "--fingerprint" ]]; then
  printf '%s\n' "$FINGERPRINT"
  exit 0
fi
if [[ "$MODE" == "--verify" ]]; then
  verify_bundle "${BUNDLE_ARGUMENT:-${WEIBEI_PI_RELINK_BUNDLE:-$BUNDLE_PATH}}"
  exit
fi
if [[ "$MODE" != "--prepare" ]]; then
  echo "usage: $0 [--fingerprint|--prepare|--verify [bundle.tar.gz]]" >&2
  exit 2
fi
if [[ -f "$LOCK" && -f "$BUNDLE_PATH" ]]; then
  verify_bundle "$BUNDLE_PATH"
  exit
fi

mkdir -p "$DOWNLOAD_DIR"
download() {
  local url="$1" sha="$2" destination="$3" actual
  if [[ ! -f "$destination" ]]; then
    /usr/bin/curl --fail --location --retry 3 --output "$destination.part" "$url"
    mv "$destination.part" "$destination"
  fi
  actual="$(/usr/bin/shasum -a 256 "$destination" | /usr/bin/awk '{print $1}')"
  [[ "$actual" == "$sha" ]] || {
    echo "Pi relink bundle failed: SHA-256 mismatch for $destination" >&2
    return 1
  }
}

PI_SOURCE="$DOWNLOAD_DIR/pi-0.82.1-source.tar.gz"
BUN_SOURCE="$DOWNLOAD_DIR/bun-1.3.14-source.tar.gz"
TINYCC_SOURCE="$DOWNLOAD_DIR/tinycc-12882eee-source.tar.gz"
WEBKIT_PREBUILT="$DOWNLOAD_DIR/bun-webkit-macos-arm64.tar.gz"
WEBKIT_COMMIT="$(json_value lgplRelink.webkit.sourceCommit)"
WEBKIT_TREE="$(json_value lgplRelink.webkit.sourceTree)"
WEBKIT_SOURCE="$DOWNLOAD_DIR/webkit-$WEBKIT_COMMIT-source.tar.gz"

download "$(json_value pi.sourceArchive.url)" "$(json_value pi.sourceArchive.sha256)" "$PI_SOURCE"
download "$(json_value bun.sourceArchive.url)" "$(json_value bun.sourceArchive.sha256)" "$BUN_SOURCE"
download "$(json_value lgplRelink.tinycc.sourceArchive.url)" "$(json_value lgplRelink.tinycc.sourceArchive.sha256)" "$TINYCC_SOURCE"
download "$(json_value lgplRelink.webkit.macosArm64Archive.url)" "$(json_value lgplRelink.webkit.macosArm64Archive.sha256)" "$WEBKIT_PREBUILT"

if [[ ! -f "$WEBKIT_SOURCE" ]]; then
  WEBKIT_GIT="$CACHE_ROOT/webkit-git"
  if [[ ! -d "$WEBKIT_GIT/.git" ]]; then
    git init -q "$WEBKIT_GIT"
    git -C "$WEBKIT_GIT" remote add origin "$(json_value lgplRelink.webkit.sourceRepository)"
  fi
  git -C "$WEBKIT_GIT" fetch --depth=1 --filter=blob:none origin "$WEBKIT_COMMIT"
  [[ "$(git -C "$WEBKIT_GIT" rev-parse 'FETCH_HEAD^{tree}')" == "$WEBKIT_TREE" ]] || {
    echo "Pi relink bundle failed: WebKit tree mismatch" >&2
    exit 3
  }
  git -C "$WEBKIT_GIT" archive --format=tar --prefix="webkit-$WEBKIT_COMMIT/" FETCH_HEAD \
    | gzip -n -9 >"$WEBKIT_SOURCE.part"
  mv "$WEBKIT_SOURCE.part" "$WEBKIT_SOURCE"
fi
[[ "$(gzip -dc "$WEBKIT_SOURCE" | git get-tar-commit-id)" == "$WEBKIT_COMMIT" ]] || {
  echo "Pi relink bundle failed: WebKit source archive commit mismatch" >&2
  exit 3
}
[[ "$(/usr/bin/shasum -a 256 "$WEBKIT_SOURCE" | /usr/bin/awk '{print $1}')" == "$(json_value lgplRelink.webkit.sourceArchive.sha256)" ]] || {
  echo "Pi relink bundle failed: WebKit source archive SHA-256 mismatch" >&2
  exit 3
}

STAGING="$CACHE_ROOT/.staging-$$"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT
MATERIAL_ROOT="$STAGING/$BUNDLE_ID"
mkdir -p "$MATERIAL_ROOT/sources" "$MATERIAL_ROOT/licenses" "$MATERIAL_ROOT/metadata"
cp "$PI_SOURCE" "$BUN_SOURCE" "$TINYCC_SOURCE" "$WEBKIT_PREBUILT" "$WEBKIT_SOURCE" "$MATERIAL_ROOT/sources/"
cp "$ROOT_DIR/Vendor/PiRuntime/LICENSE" "$MATERIAL_ROOT/licenses/PI-MIT.txt"
cp "$ROOT_DIR/Vendor/PiRuntime/BUN_LICENSE.md" "$MATERIAL_ROOT/licenses/BUN-LICENSE.md"
cp "$ROOT_DIR/Vendor/PiRuntime/LGPL-2.0.txt" "$ROOT_DIR/Vendor/PiRuntime/LGPL-2.1.txt" "$MATERIAL_ROOT/licenses/"
cp "$INPUTS" "$ROOT_DIR/Vendor/PiRuntime/RELINK.md" "$MATERIAL_ROOT/metadata/"
printf '%s' "$FINGERPRINT" >"$MATERIAL_ROOT/bundle-fingerprint.txt"
(cd "$MATERIAL_ROOT" && /usr/bin/shasum -a 256 sources/* licenses/* metadata/* >SHA256SUMS)
COPYFILE_DISABLE=1 /usr/bin/tar -czf "$BUNDLE_PATH.part" -C "$STAGING" "$BUNDLE_ID"
mv "$BUNDLE_PATH.part" "$BUNDLE_PATH"
/usr/bin/shasum -a 256 "$BUNDLE_PATH"
printf '%s\n' "$BUNDLE_PATH"
echo "Update Vendor/PiRuntime/relink-bundle.lock.json with this fingerprint and SHA-256, then rerun --verify." >&2
