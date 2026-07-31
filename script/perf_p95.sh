#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <perf-log> <metric-name> [minimum-samples] [warmup-samples]" >&2
  echo "       $0 --self-check" >&2
}

if [[ "${1:-}" == "--self-check" ]]; then
  fixture="$(mktemp "${TMPDIR:-/tmp}/weibei-perf-p95.XXXXXX")"
  trap 'rm -f "$fixture"' EXIT
  for value in $(seq 1 110); do
    printf '[PERF-weibei-2] scenario=self-check sample=%03d name=fixture.metric ms=%d.000 main=0 outcome=completed\n' \
      "$value" "$value" >>"$fixture"
  done
  result="$("$0" "$fixture" fixture.metric 100 10)"
  [[ "$result" == *"samples=100"* && "$result" == *"p95_ms=105.000"* ]]
  echo "WeiBei performance p95 parser self-check passed"
  exit 0
fi

if [[ $# -lt 2 || $# -gt 4 ]]; then
  usage
  exit 2
fi

log_path="$1"
metric_name="$2"
minimum_samples="${3:-1}"
warmup_samples="${4:-0}"
if [[ ! -f "$log_path"
    || ! "$minimum_samples" =~ ^[0-9]+$
    || ! "$warmup_samples" =~ ^[0-9]+$ ]]; then
  usage
  exit 2
fi

values_file="$(mktemp "${TMPDIR:-/tmp}/weibei-perf-values.XXXXXX")"
scenarios_file="$(mktemp "${TMPDIR:-/tmp}/weibei-perf-scenarios.XXXXXX")"
trap 'rm -f "$values_file" "$scenarios_file"' EXIT

awk -v target="$metric_name" -v scenarios="$scenarios_file" '
  /^\[PERF-weibei-2\]/ {
    name = ""
    milliseconds = ""
    scenario = ""
    outcome = ""
    for (field_index = 1; field_index <= NF; field_index += 1) {
      split($field_index, pair, "=")
      if (pair[1] == "name") name = pair[2]
      if (pair[1] == "ms") milliseconds = pair[2]
      if (pair[1] == "scenario") scenario = pair[2]
      if (pair[1] == "outcome") outcome = pair[2]
    }
    if (name == target && milliseconds != "" && (outcome == "" || outcome == "completed")) {
      print milliseconds
      if (scenario != "") print scenario > scenarios
    }
  }
' "$log_path" | tail -n "+$((warmup_samples + 1))" | sort -n >"$values_file"

sample_count="$(wc -l <"$values_file" | tr -d ' ')"
if (( sample_count < minimum_samples )); then
  echo "insufficient samples: metric=$metric_name samples=$sample_count required=$minimum_samples" >&2
  exit 3
fi

rank=$(( (sample_count * 95 + 99) / 100 ))
p95_ms="$(sed -n "${rank}p" "$values_file")"
scenario_count="$(sort -u "$scenarios_file" | awk 'NF { count += 1 } END { print count + 0 }')"
printf 'metric=%s samples=%s p95_ms=%s scenarios=%s\n' \
  "$metric_name" "$sample_count" "$p95_ms" "$scenario_count"
