#!/usr/bin/env bash
# Prepare the embedded Pi agent as: official Node + npm @earendil-works/pi-coding-agent.
# Layout (under PiRuntime/):
#   node/bin/node          — signed Node binary (integrity in binary.sha256)
#   agent/                 — production npm install of pi-coding-agent
#   bin/pi                 — wrapper: exec node → dist/cli.js
#   bin/package.json       — agent package metadata (version pin)
#   bin/theme/             — theme assets copied for layout compatibility
#   manifest.json, LICENSE, THIRD_PARTY_NOTICES.md, artifact.sha256
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/Vendor/PiRuntime/manifest.json"
VERSION="$(/usr/bin/plutil -extract piVersion raw -o - "$MANIFEST")"
RUNTIME_KIND="$(/usr/bin/plutil -extract runtimeKind raw -o - "$MANIFEST" 2>/dev/null || echo "node")"
NPM_PACKAGE="$(/usr/bin/plutil -extract npmPackage raw -o - "$MANIFEST" 2>/dev/null || echo "@earendil-works/pi-coding-agent")"
NODE_VERSION="$(/usr/bin/plutil -extract node.version raw -o - "$MANIFEST")"
HOST_ARCH="${WEIBEI_PI_ARCH:-$(uname -m)}"

if [[ "$RUNTIME_KIND" != "node" ]]; then
  echo "embedded PI preparation failed: manifest runtimeKind must be node (got $RUNTIME_KIND)" >&2
  exit 2
fi

case "$HOST_ARCH" in
  arm64)
    ARTIFACT_KEY="darwin-arm64"
    NODE_ARCH="arm64"
    ;;
  x86_64)
    ARTIFACT_KEY="darwin-x64"
    NODE_ARCH="x64"
    ;;
  *)
    echo "embedded PI preparation failed: unsupported macOS architecture $HOST_ARCH" >&2
    exit 2
    ;;
esac

NODE_ARCHIVE="$(/usr/bin/plutil -extract "node.artifacts.$ARTIFACT_KEY.archive" raw -o - "$MANIFEST")"
NODE_SHA256="$(/usr/bin/plutil -extract "node.artifacts.$ARTIFACT_KEY.sha256" raw -o - "$MANIFEST")"
NODE_URL="$(/usr/bin/plutil -extract "node.artifacts.$ARTIFACT_KEY.url" raw -o - "$MANIFEST")"
CACHE_ROOT="${WEIBEI_PI_CACHE_DIR:-$ROOT_DIR/.build/pi-runtime}"
DOWNLOAD_DIR="$CACHE_ROOT/downloads"
RUNTIME_PARENT="$CACHE_ROOT/node-$NODE_VERSION-$VERSION/$ARTIFACT_KEY"
RUNTIME_DIR="$RUNTIME_PARENT/PiRuntime"
RUNTIME_NODE="$RUNTIME_DIR/node/bin/node"
RUNTIME_WRAPPER="$RUNTIME_DIR/bin/pi"
AGENT_CLI="$RUNTIME_DIR/agent/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"

runtime_is_ready() {
  [[ -x "$RUNTIME_NODE" ]] \
    && [[ -x "$RUNTIME_WRAPPER" ]] \
    && [[ -f "$AGENT_CLI" ]] \
    && [[ -f "$RUNTIME_DIR/bin/package.json" ]] \
    && [[ -f "$RUNTIME_DIR/bin/theme/dark.json" ]] \
    && [[ -f "$RUNTIME_DIR/bin/theme/light.json" ]] \
    && [[ -f "$RUNTIME_DIR/LICENSE" ]] \
    && [[ -f "$RUNTIME_DIR/THIRD_PARTY_NOTICES.md" ]] \
    && [[ -f "$RUNTIME_DIR/binary.sha256" ]] \
    && [[ -f "$RUNTIME_DIR/artifact.sha256" ]] \
    && cmp -s "$MANIFEST" "$RUNTIME_DIR/manifest.json" \
    && /usr/bin/codesign --verify --strict "$RUNTIME_NODE" >/dev/null 2>&1 \
    && [[ "$(/usr/bin/shasum -a 256 "$RUNTIME_NODE" | /usr/bin/awk '{print $1}')" == "$(<"$RUNTIME_DIR/binary.sha256")" ]] \
    && [[ "$("$RUNTIME_WRAPPER" --version 2>/dev/null)" == "$VERSION" ]]
}

if runtime_is_ready; then
  printf '%s\n' "$RUNTIME_DIR"
  exit 0
fi

mkdir -p "$DOWNLOAD_DIR" "$RUNTIME_PARENT"
LOCK_DIR="$CACHE_ROOT/.prepare-node-$ARTIFACT_KEY.lock"
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

NODE_ARCHIVE_PATH="${WEIBEI_NODE_ARCHIVE:-$DOWNLOAD_DIR/$NODE_ARCHIVE}"
if [[ ! -f "$NODE_ARCHIVE_PATH" ]]; then
  echo "downloading Node.js $NODE_VERSION for $HOST_ARCH" >&2
  /usr/bin/curl --fail --location --retry 3 --output "$DOWNLOAD_DIR/$NODE_ARCHIVE.part" "$NODE_URL"
  mv "$DOWNLOAD_DIR/$NODE_ARCHIVE.part" "$DOWNLOAD_DIR/$NODE_ARCHIVE"
  NODE_ARCHIVE_PATH="$DOWNLOAD_DIR/$NODE_ARCHIVE"
fi

ACTUAL_NODE_SHA256="$(/usr/bin/shasum -a 256 "$NODE_ARCHIVE_PATH" | /usr/bin/awk '{print $1}')"
if [[ "$ACTUAL_NODE_SHA256" != "$NODE_SHA256" ]]; then
  echo "embedded PI preparation failed: SHA-256 mismatch for $NODE_ARCHIVE_PATH" >&2
  exit 3
fi

STAGING_DIR="$RUNTIME_PARENT/.staging-$$"
rm -rf "$STAGING_DIR"
mkdir -p \
  "$STAGING_DIR/node-extract" \
  "$STAGING_DIR/PiRuntime/bin/theme" \
  "$STAGING_DIR/PiRuntime/node" \
  "$STAGING_DIR/PiRuntime/agent"

/usr/bin/tar -xzf "$NODE_ARCHIVE_PATH" -C "$STAGING_DIR/node-extract"
NODE_PREFIX="$STAGING_DIR/node-extract/node-v${NODE_VERSION}-darwin-${NODE_ARCH}"
if [[ ! -x "$NODE_PREFIX/bin/node" ]]; then
  echo "embedded PI preparation failed: Node archive missing bin/node" >&2
  exit 4
fi

# Keep a minimal Node tree: binary + license notices (no npm/npx/system tools needed at runtime).
mkdir -p "$STAGING_DIR/PiRuntime/node/bin"
cp "$NODE_PREFIX/bin/node" "$STAGING_DIR/PiRuntime/node/bin/node"
chmod 755 "$STAGING_DIR/PiRuntime/node/bin/node"
if [[ -f "$NODE_PREFIX/LICENSE" ]]; then
  cp "$NODE_PREFIX/LICENSE" "$STAGING_DIR/PiRuntime/node/LICENSE"
fi
if [[ -d "$NODE_PREFIX/share/doc" ]]; then
  mkdir -p "$STAGING_DIR/PiRuntime/node/share"
  cp -R "$NODE_PREFIX/share/doc" "$STAGING_DIR/PiRuntime/node/share/doc" 2>/dev/null || true
fi

echo "installing $NPM_PACKAGE@$VERSION (production only)" >&2
cat >"$STAGING_DIR/PiRuntime/agent/package.json" <<EOF
{
  "name": "weibei-embedded-pi-agent",
  "private": true,
  "version": "0.0.0",
  "dependencies": {
    "$NPM_PACKAGE": "$VERSION"
  }
}
EOF
(
  cd "$STAGING_DIR/PiRuntime/agent"
  npm install --omit=dev --no-audit --no-fund --ignore-scripts
)

AGENT_PKG="$STAGING_DIR/PiRuntime/agent/node_modules/@earendil-works/pi-coding-agent"
if [[ ! -f "$AGENT_PKG/dist/cli.js" ]]; then
  echo "embedded PI preparation failed: npm package missing dist/cli.js" >&2
  exit 4
fi
if [[ ! -f "$AGENT_PKG/package.json" ]]; then
  echo "embedded PI preparation failed: npm package missing package.json" >&2
  exit 4
fi

cp "$AGENT_PKG/package.json" "$STAGING_DIR/PiRuntime/bin/package.json"
# Themes for layout compatibility (RPC uses --no-themes; assets still packaged).
if [[ -d "$AGENT_PKG/dist/modes/interactive/theme" ]]; then
  cp "$AGENT_PKG/dist/modes/interactive/theme/"*.json "$STAGING_DIR/PiRuntime/bin/theme/" 2>/dev/null || true
fi
if [[ ! -f "$STAGING_DIR/PiRuntime/bin/theme/dark.json" ]]; then
  printf '%s\n' '{}' >"$STAGING_DIR/PiRuntime/bin/theme/dark.json"
fi
if [[ ! -f "$STAGING_DIR/PiRuntime/bin/theme/light.json" ]]; then
  printf '%s\n' '{}' >"$STAGING_DIR/PiRuntime/bin/theme/light.json"
fi

cat >"$STAGING_DIR/PiRuntime/bin/pi" <<'WRAPPER'
#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
NODE_BIN="$ROOT/node/bin/node"
CLI="$ROOT/agent/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
if [[ ! -x "$NODE_BIN" ]]; then
  echo "weibei embedded pi: missing Node binary at $NODE_BIN" >&2
  exit 127
fi
if [[ ! -f "$CLI" ]]; then
  echo "weibei embedded pi: missing agent cli at $CLI" >&2
  exit 127
fi
exec "$NODE_BIN" "$CLI" "$@"
WRAPPER
chmod 755 "$STAGING_DIR/PiRuntime/bin/pi"

cp "$MANIFEST" "$STAGING_DIR/PiRuntime/manifest.json"
cp "$ROOT_DIR/Vendor/PiRuntime/LICENSE" "$STAGING_DIR/PiRuntime/LICENSE"
cp "$ROOT_DIR/Vendor/PiRuntime/THIRD_PARTY_NOTICES.md" "$STAGING_DIR/PiRuntime/THIRD_PARTY_NOTICES.md"
{
  printf '%s  %s\n' "$NODE_SHA256" "$NODE_ARCHIVE"
  printf '%s  %s@%s\n' "$(/usr/bin/shasum -a 256 "$STAGING_DIR/PiRuntime/agent/package-lock.json" | /usr/bin/awk '{print $1}')" "$NPM_PACKAGE" "$VERSION"
} >"$STAGING_DIR/PiRuntime/artifact.sha256"

/usr/bin/xattr -dr com.apple.quarantine "$STAGING_DIR/PiRuntime" 2>/dev/null || true
/usr/bin/codesign --force --sign - --timestamp=none "$STAGING_DIR/PiRuntime/node/bin/node" >/dev/null
/usr/bin/codesign --verify --strict "$STAGING_DIR/PiRuntime/node/bin/node"
/usr/bin/shasum -a 256 "$STAGING_DIR/PiRuntime/node/bin/node" | /usr/bin/awk '{print $1}' >"$STAGING_DIR/PiRuntime/binary.sha256"

rm -rf "$RUNTIME_DIR"
mv "$STAGING_DIR/PiRuntime" "$RUNTIME_DIR"
STAGING_DIR=""

if ! runtime_is_ready; then
  echo "embedded PI preparation failed: prepared runtime did not pass validation" >&2
  exit 5
fi

printf '%s\n' "$RUNTIME_DIR"
