#!/usr/bin/env bash
set -euo pipefail

MAX_NET_GROWTH=50
FROZEN_FILES=(
  "Sources/WeiBei/Stores/WorkspaceStore.swift"
  "Sources/WeiBeiCore/AgentResources/extension.ts"
  "Sources/WeiBei/Views/NotesAgentView.swift"
  "Sources/WeiBei/Views/ReaderView.swift"
)

line_count() {
  local revision="$1"
  local path="$2"
  if git cat-file -e "$revision:$path" 2>/dev/null; then
    git show "$revision:$path" | wc -l | tr -d ' '
  else
    printf '0\n'
  fi
}

exemption_reason() {
  printf '%s\n' "${PR_BODY:-}" | awk '
    match($0, /\[growth-exempt:[[:space:]]*[^]]+\]/) {
      reason = substr($0, RSTART, RLENGTH)
      sub(/^\[growth-exempt:[[:space:]]*/, "", reason)
      sub(/[[:space:]]*\]$/, "", reason)
      if (length(reason) > 0) {
        print reason
        exit
      }
    }
  '
}

check_growth() {
  local base="$1"
  local head="$2"
  local failed=false
  local path base_lines head_lines growth

  git rev-parse --verify "$base^{commit}" >/dev/null
  git rev-parse --verify "$head^{commit}" >/dev/null

  if [[ "${GROWTH_EXEMPT_LABEL:-false}" == "true" && -n "$(exemption_reason)" ]]; then
    echo "Frozen-file growth exemption accepted"
    return 0
  fi

  for path in "${FROZEN_FILES[@]}"; do
    base_lines="$(line_count "$base" "$path")"
    head_lines="$(line_count "$head" "$path")"
    growth=$((head_lines - base_lines))
    printf '%s: base=%s head=%s growth=%+d\n' "$path" "$base_lines" "$head_lines" "$growth"
    if (( growth > MAX_NET_GROWTH )); then
      failed=true
    fi
  done

  if [[ "$failed" == "true" ]]; then
    echo "A frozen file grew by more than ${MAX_NET_GROWTH} lines" >&2
    return 1
  fi
}

self_check() {
  local script_path file base pass_head fail_head
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  self_check_fixture="$(mktemp -d "${TMPDIR:-/tmp}/weibei-growth-check.XXXXXX")"
  trap 'rm -rf "$self_check_fixture"' EXIT
  file="$self_check_fixture/${FROZEN_FILES[0]}"

  git -C "$self_check_fixture" init -q
  git -C "$self_check_fixture" config user.name "WeiBei Self Check"
  git -C "$self_check_fixture" config user.email "self-check@invalid"
  mkdir -p "$(dirname "$file")"
  printf 'base\n' >"$file"
  git -C "$self_check_fixture" add .
  git -C "$self_check_fixture" commit -qm base
  base="$(git -C "$self_check_fixture" rev-parse HEAD)"

  for _ in $(seq 1 50); do printf 'allowed\n' >>"$file"; done
  git -C "$self_check_fixture" commit -qam allowed
  pass_head="$(git -C "$self_check_fixture" rev-parse HEAD)"
  (cd "$self_check_fixture" && "$script_path" "$base" "$pass_head") >/dev/null

  printf 'blocked\n' >>"$file"
  git -C "$self_check_fixture" commit -qam blocked
  fail_head="$(git -C "$self_check_fixture" rev-parse HEAD)"
  if (cd "$self_check_fixture" && \
    GROWTH_EXEMPT_LABEL=false PR_BODY='' \
    "$script_path" "$base" "$fail_head") >/dev/null 2>&1; then
    echo "file growth self-check failed: 51 lines were accepted" >&2
    return 1
  fi

  (cd "$self_check_fixture" && \
    GROWTH_EXEMPT_LABEL=true \
    PR_BODY='[growth-exempt: self-check]' \
    "$script_path" "$base" "$fail_head") >/dev/null

  echo "WeiBei file growth self-check passed"
}

if [[ "${1:-}" == "--self-check" ]]; then
  self_check
  exit 0
fi

if (( $# != 2 )); then
  echo "usage: $0 <base-sha> <head-sha> | --self-check" >&2
  exit 2
fi

check_growth "$1" "$2"
