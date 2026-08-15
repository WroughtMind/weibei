#!/usr/bin/env bash
set -euo pipefail

# Guard: source-string assertions in WeiBeiSelfCheck must declare a SAFETY reason.
# Deleting a retained safety assertion must turn this script red.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELFCHECK_DIR="$ROOT/Sources/WeiBeiSelfCheck"

REQUIRED=(
  "SAFETY:note-repair-order"
  "SAFETY:note-repair-oneshot"
  "SAFETY:backup-before-restore"
  "SAFETY:template-writeback-block"
  "SAFETY:rename-sentinel"
  "SAFETY:lastknown-fallback"
  "SAFETY:pending-unsaved-vs-missing"
  "SAFETY:pi-owns-credentials"
  "SAFETY:no-swallowed-link-failure"
  "SAFETY:blank-new-note"
)

if [[ "${1:-}" == "--self-check" ]]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/weibei-source-assert.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  cat >"$tmp/ok.swift" <<'SWIFT'
expect(workspaceStoreSource.contains("guard !noteDivergenceRepairDidRun else { return }"),
    "SAFETY:note-repair-oneshot keep this")
SWIFT
  if ! grep -q 'SAFETY:note-repair-oneshot' "$tmp/ok.swift"; then
    echo "self-check fixture missing SAFETY tag" >&2
    exit 1
  fi
  echo "WeiBei SelfCheck source-assertion guard self-check passed"
  exit 0
fi

missing=()
for key in "${REQUIRED[@]}"; do
  if ! grep -R -F -q -- "$key" "$SELFCHECK_DIR"; then
    missing+=("$key")
  fi
done
if (( ${#missing[@]} > 0 )); then
  printf 'missing retained SAFETY assertions:\n' >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

# A source-string probe must sit near an expect message that starts with SAFETY:
python3 - "$SELFCHECK_DIR" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
bad = []
for path in sorted(root.glob("*.swift")):
    lines = path.read_text().splitlines()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("let ") and "readSource(" in line:
            continue
        is_file_source_probe = (
            "Source.contains(" in line
            or "Source.range(" in line
        )
        if not is_file_source_probe:
            continue
        window = "\n".join(lines[max(0, index - 8): index + 30])
        if "SAFETY:" not in window:
            bad.append(f"{path.name}:{index + 1}: {stripped[:100]}")
if bad:
    print("source-string probes without a nearby SAFETY reason:", file=sys.stderr)
    for item in bad:
        print(f"  {item}", file=sys.stderr)
    sys.exit(1)
print("WeiBei SelfCheck source-assertion guard passed")
PY
