#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCE_DIR="$ROOT_DIR/Sources/WeiBei/Resources"
EDITOR_SOURCE="$ROOT_DIR/Sources/WeiBei/WebEditor/src/editor.js"
RICH_RUNTIME_DIR="$ROOT_DIR/Prototypes/RichAnswerWebRuntime"
if [[ -f "$ROOT_DIR/Web/Editor/src/editor.js" ]]; then
  EDITOR_SOURCE="$ROOT_DIR/Web/Editor/src/editor.js"
fi
if [[ -f "$ROOT_DIR/Web/RichAnswerRuntime/package.json" ]]; then
  RICH_RUNTIME_DIR="$ROOT_DIR/Web/RichAnswerRuntime"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/weibei-generated-resources.XXXXXX")"
EDITOR_STAGE="$TEMP_DIR/Editor"
RICH_STAGE="$TEMP_DIR/RichAnswerRuntime"
STATUS_BEFORE="$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all)"

# Removes only this invocation's private staging directory.
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Fails with a focused message when one generated file differs from its committed copy.
compare_file() {
  local generated="$1" committed="$2" label="$3"
  if [[ ! -f "$committed" ]]; then
    echo "generated resource check failed: missing committed $label at $committed" >&2
    return 1
  fi
  if ! /usr/bin/cmp -s "$generated" "$committed"; then
    echo "generated resource check failed: committed $label is stale" >&2
    echo "  generated: $generated" >&2
    echo "  committed: $committed" >&2
    return 1
  fi
}

if [[ ! -x "$ROOT_DIR/node_modules/.bin/esbuild" ]]; then
  echo "generated resource check failed: run npm ci at the repository root first" >&2
  exit 2
fi
if [[ ! -x "$RICH_RUNTIME_DIR/node_modules/.bin/vite" ]]; then
  echo "generated resource check failed: run npm ci in $RICH_RUNTIME_DIR first" >&2
  exit 2
fi

mkdir -p "$EDITOR_STAGE" "$RICH_STAGE"
"$ROOT_DIR/node_modules/.bin/esbuild" "$EDITOR_SOURCE" \
  --bundle \
  --format=iife \
  --outfile="$EDITOR_STAGE/editor.js" \
  --minify \
  --loader:.woff=file \
  --loader:.woff2=file \
  --loader:.ttf=file \
  '--asset-names=fonts/[name]' \
  --log-level=warning

compare_file "$EDITOR_STAGE/editor.js" "$RESOURCE_DIR/Editor/editor.js" "editor JavaScript"
compare_file "$EDITOR_STAGE/editor.css" "$RESOURCE_DIR/Editor/editor.css" "editor CSS"
if [[ -d "$EDITOR_STAGE/fonts" ]]; then
  if ! /usr/bin/diff -qr "$EDITOR_STAGE/fonts" "$RESOURCE_DIR/Editor/fonts" >/dev/null; then
    echo "generated resource check failed: committed editor fonts are stale" >&2
    /usr/bin/diff -qr "$EDITOR_STAGE/fonts" "$RESOURCE_DIR/Editor/fonts" >&2 || true
    exit 1
  fi
fi

(
  cd "$RICH_RUNTIME_DIR"
  ./node_modules/.bin/vite build --outDir "$RICH_STAGE" --emptyOutDir
) >/dev/null

compare_file "$RICH_STAGE/index.html" "$RESOURCE_DIR/rich-answer.html" "Rich Answer HTML"
compare_file "$RICH_STAGE/rich-answer-runtime.css" "$RESOURCE_DIR/rich-answer-runtime.css" "Rich Answer CSS"
compare_file "$RICH_STAGE/rich-answer-runtime.js" "$RESOURCE_DIR/rich-answer-runtime.js" "Rich Answer JavaScript"

STATUS_AFTER="$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all)"
if [[ "$STATUS_AFTER" != "$STATUS_BEFORE" ]]; then
  echo "generated resource check failed: verification changed the worktree" >&2
  /usr/bin/diff -u <(printf '%s\n' "$STATUS_BEFORE") <(printf '%s\n' "$STATUS_AFTER") >&2 || true
  exit 1
fi

echo "generated resources are reproducible"
