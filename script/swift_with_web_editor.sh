#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f Package.swift || ! -f package.json || ! -d Sources/WeiBei ]]; then
  echo "legacy Swift wrapper must be run from the repository root" >&2
  exit 2
fi

swift run WeiBeiDevTool prepare web-editor
exec swift "$@"
