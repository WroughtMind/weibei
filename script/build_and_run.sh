#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f Package.swift || ! -f package.json || ! -d Sources/WeiBei ]]; then
  echo "legacy launcher must be run from the repository root" >&2
  exit 2
fi

case "${1:-run}" in
  run)
    exec swift run WeiBeiDevTool run
    ;;
  check|--check|verify-only|--verify-only)
    exec swift run WeiBeiDevTool check
    ;;
  package|--package)
    exec swift run WeiBeiDevTool package
    ;;
  debug|--debug)
    exec swift run WeiBeiDevTool run --debug
    ;;
  logs|--logs)
    exec swift run WeiBeiDevTool run --logs
    ;;
  telemetry|--telemetry)
    exec swift run WeiBeiDevTool run --telemetry
    ;;
  verify|--verify)
    if [[ "${2:-}" == "--visual-verify" || "${2:-}" == "visual-verify" ]]; then
      exec swift run WeiBeiDevTool verify --visual
    fi
    exec swift run WeiBeiDevTool verify
    ;;
  visual-verify|--visual-verify)
    exec swift run WeiBeiDevTool verify --visual
    ;;
  *)
    echo "usage: $0 [run|check|package|--debug|--logs|--telemetry|--verify [--visual-verify]|--visual-verify]" >&2
    exit 2
    ;;
esac
