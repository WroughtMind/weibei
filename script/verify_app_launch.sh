#!/usr/bin/env bash
set -euo pipefail
# Only an isolated CI desktop may be opened automatically.
[[ "${CI:-}" == true ]] || { echo '本机候选请在画中画验收。' >&2; exit 1; }
APP="$(cd "${1:?application path required}" && pwd)"
BINARY="$APP/Contents/MacOS/WeiBei"
pid=""
open -n "$APP"
for _ in {1..120}; do
  while IFS= read -r candidate; do
    command="$(ps -p "$candidate" -o command= 2>/dev/null || true)"
    if [[ "$command" == "$BINARY" || "$command" == "$BINARY "* ]]; then
      pid="$candidate"
      break 2
    fi
  done < <(pgrep -x WeiBei 2>/dev/null || true)
  sleep 0.25
done
[[ -n "$pid" ]] || { echo '应用未能启动。' >&2; exit 2; }
trap 'kill -TERM "$pid" 2>/dev/null || true' EXIT
sleep 5
kill -0 "$pid" || { echo '应用启动后异常退出。' >&2; exit 3; }
kill -TERM "$pid"
for _ in {1..200}; do
  if ! kill -0 "$pid" 2>/dev/null; then
    trap - EXIT
    echo 'production_launch=passed'
    exit 0
  fi
  sleep 0.25
done
echo '应用未能正常退出。' >&2
exit 4
