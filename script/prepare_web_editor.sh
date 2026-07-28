#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR_RESOURCE_DIR="$ROOT_DIR/Sources/WeiBei/Resources/Editor"

if ! command -v npm >/dev/null 2>&1; then
  echo "web editor build failed: Node.js 22 and npm are required; install them, then rerun this command" >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/package-lock.json" ]]; then
  echo "web editor build failed: missing package-lock.json" >&2
  exit 2
fi
if [[ ! -x "$ROOT_DIR/node_modules/.bin/esbuild" ]]; then
  echo "Installing locked Node.js dependencies for the web editor..."
  npm --prefix "$ROOT_DIR" ci
fi

echo "Building web editor resources..."
npm --prefix "$ROOT_DIR" run build:editor

for resource in \
  "$EDITOR_RESOURCE_DIR/editor.js" \
  "$EDITOR_RESOURCE_DIR/editor.css" \
  "$EDITOR_RESOURCE_DIR/fonts/KaTeX_Main-Regular.woff2"; do
  if [[ ! -s "$resource" ]]; then
    echo "web editor build failed: missing generated resource ${resource#"$ROOT_DIR/"}" >&2
    exit 3
  fi
done
