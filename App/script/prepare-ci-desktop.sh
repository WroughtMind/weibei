#!/usr/bin/env bash
set -euo pipefail
[[ "${CI:-}" == true ]] || { echo 'only the isolated CI desktop may be prepared' >&2; exit 1; }
[[ "$(uname -m)" == x86_64 ]] || exit 0
mkdir -p "$RUNNER_TEMP/weibei-native-full-screen-evidence"
service="gui/$(id -u)/com.apple.iconservices.iconservicesagent"
record="$RUNNER_TEMP/weibei-native-full-screen-evidence/ci-iconservices-before.log"
launchctl print "$service" > "$record"
# https://github.com/actions/runner-images/issues/14751
if grep -q 'last terminating signal = Abort trap: 6' "$record"; then
  launchctl bootout "$service"
  launchctl disable "$service"
  killall Dock
fi
