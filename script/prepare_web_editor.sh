#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR_RESOURCE_DIR="$ROOT_DIR/Sources/WeiBei/Resources/Editor"
NODE_VERSION_FILE="$ROOT_DIR/.nvmrc"
DEPENDENCY_STATE_FILE="$ROOT_DIR/node_modules/.weibei-dependency-state.sha256"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "web editor build failed: Node.js 22 and npm are required; install them, then rerun this command" >&2
  exit 1
fi
if [[ ! -s "$NODE_VERSION_FILE" ]]; then
  echo "web editor build failed: missing .nvmrc" >&2
  exit 2
fi
EXPECTED_NODE_VERSION="$(/usr/bin/tr -d 'v\r\n[:space:]' <"$NODE_VERSION_FILE")"
ACTUAL_NODE_VERSION="$(node --version | /usr/bin/tr -d 'v\r\n[:space:]')"
if [[ "$ACTUAL_NODE_VERSION" != "$EXPECTED_NODE_VERSION" ]]; then
  echo "web editor build failed: Node.js $EXPECTED_NODE_VERSION is required, but $ACTUAL_NODE_VERSION is active; run 'nvm use'" >&2
  exit 3
fi
if [[ ! -s "$ROOT_DIR/package.json" || ! -s "$ROOT_DIR/package-lock.json" ]]; then
  echo "web editor build failed: package.json and package-lock.json are both required" >&2
  exit 4
fi

DEPENDENCY_STATE="$(
  /usr/bin/shasum -a 256 "$ROOT_DIR/package.json" "$ROOT_DIR/package-lock.json" \
    | /usr/bin/shasum -a 256 \
    | /usr/bin/awk '{print $1}'
)"
INSTALLED_STATE=""
if [[ -s "$DEPENDENCY_STATE_FILE" ]]; then
  INSTALLED_STATE="$(<"$DEPENDENCY_STATE_FILE")"
fi
if [[ "$INSTALLED_STATE" != "$DEPENDENCY_STATE" ]] \
  || [[ ! -x "$ROOT_DIR/node_modules/.bin/esbuild" ]] \
  || ! npm --prefix "$ROOT_DIR" ls --all >/dev/null 2>&1; then
  echo "Installing locked Node.js dependencies for the web editor..."
  npm --prefix "$ROOT_DIR" ci
  npm --prefix "$ROOT_DIR" ls --all >/dev/null
  printf '%s\n' "$DEPENDENCY_STATE" >"$DEPENDENCY_STATE_FILE"
fi

echo "Building web editor resources..."
npm --prefix "$ROOT_DIR" run build:editor

for resource in \
  "$EDITOR_RESOURCE_DIR/editor.js" \
  "$EDITOR_RESOURCE_DIR/editor.css" \
  "$EDITOR_RESOURCE_DIR/fonts/KaTeX_Main-Regular.woff2"; do
  if [[ ! -s "$resource" ]]; then
    echo "web editor build failed: missing generated resource ${resource#"$ROOT_DIR/"}" >&2
    exit 5
  fi
done
