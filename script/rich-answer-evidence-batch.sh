#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_SCRIPT="$ROOT_DIR/script/rich-answer-evidence-smoke.sh"
SMOKE_RUNNER="${RICH_ANSWER_EVIDENCE_SMOKE_SCRIPT_OVERRIDE:-$SMOKE_SCRIPT}"
VISUAL_SCRIPT="$ROOT_DIR/script/rich-answer-visual-gate.swift"
BATCH_SCRIPT="$ROOT_DIR/script/rich-answer-evidence-batch.sh"
INPUT_PATH=""
OUTPUT_DIR="${RICH_ANSWER_SCREENSHOT_BATCH_DIR:-${TMPDIR:-/tmp}/weibei-rich-answer-screenshots-$(date +%Y%m%d-%H%M%S)}"
JOBS=1
RESUME=0
LIMIT=""
ONLY_CASE=""
FIXTURE_SMOKE=0
MIN_FREE_KB="${RICH_ANSWER_MIN_FREE_KB:-20971520}"
KEEP_APP_CACHE="${RICH_ANSWER_KEEP_APP_CACHE:-0}"
BUILD_CACHE_DIR=""

available_free_kb() {
  df -Pk "$1" | awk 'NR == 2 { print $4 }'
}

ensure_free_space() {
  local target="$1"
  local phase="$2"
  local available
  available="$(available_free_kb "$target")"
  if [[ ! "$available" =~ ^[0-9]+$ ]]; then
    echo "rich-answer screenshot batch cannot read free disk space during $phase: $target" >&2
    return 74
  fi
  if (( available < MIN_FREE_KB )); then
    echo "rich-answer screenshot batch stopped during $phase: ${available} KiB free, requires at least ${MIN_FREE_KB} KiB." >&2
    return 75
  fi
}

cleanup_app_cache() {
  if [[ "$KEEP_APP_CACHE" != "1" && -n "$BUILD_CACHE_DIR" && -d "$BUILD_CACHE_DIR" ]]; then
    rm -rf -- "$BUILD_CACHE_DIR"
  fi
}

usage() {
  cat <<'USAGE'
usage:
  script/rich-answer-evidence-batch.sh --index <run-or-shard-index.json> [--output-dir dir] [--resume] [--jobs 1|2]
  script/rich-answer-evidence-batch.sh --run <run-dir> [--output-dir dir] [--resume] [--jobs 1|2]
  script/rich-answer-evidence-batch.sh --fixture-smoke [--output-dir dir]

notes:
  - Uses WEIBEI_VERIFY_RICH_ANSWER_REPLAY for each record.
  - Default is serial. Only --jobs 2 enables two lanes; 4/6 lanes are intentionally rejected.
  - --resume skips only when record/image SHA-256, case id, round, qualityGate, and reviewStatus all match.
  - The temporary app build cache is removed on exit unless RICH_ANSWER_KEEP_APP_CACHE=1.
USAGE
}

abs_path() {
  local target="$1"
  if [[ -d "$target" ]]; then
    (cd "$target" && pwd -P)
  else
    local dir
    local base
    dir="$(dirname "$target")"
    base="$(basename "$target")"
    printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
  fi
}

sanitize_name() {
  printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

file_size_bytes() {
  wc -c <"$1" | tr -d ' '
}

tracked_diff_sha256() {
  git -C "$ROOT_DIR" diff --binary --no-ext-diff HEAD -- 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

hash_paths_json() {
  local list_file="$1"
  local tsv_file="$2"
  : >"$tsv_file"
  while IFS= read -r relative_path; do
    [[ -n "$relative_path" && -f "$ROOT_DIR/$relative_path" ]] || continue
    printf '%s\t%s\t%s\n' \
      "$relative_path" \
      "$(sha256_file "$ROOT_DIR/$relative_path")" \
      "$(file_size_bytes "$ROOT_DIR/$relative_path")" >>"$tsv_file"
  done <"$list_file"
  jq -Rn '[inputs | split("\t") | select(length == 3) | {path: .[0], sha256: .[1], bytes: (.[2] | tonumber)}]' <"$tsv_file"
}

append_lock_file() {
  local output_file="$1"
  local relative_path="$2"
  [[ -n "$relative_path" && -f "$ROOT_DIR/$relative_path" ]] || return 0
  printf '%s\n' "$relative_path" >>"$output_file"
}

append_lock_tree() {
  local output_file="$1"
  local relative_dir="$2"
  [[ -n "$relative_dir" && -d "$ROOT_DIR/$relative_dir" ]] || return 0
  (cd "$ROOT_DIR" && find "$relative_dir" -type f \
    ! -name '.DS_Store' \
    ! -path '*/.build/*' \
    ! -path '*/DerivedData/*' \
    -print) >>"$output_file"
}

append_lock_matches() {
  local output_file="$1"
  local relative_dir="$2"
  local name_pattern="$3"
  [[ -n "$relative_dir" && -d "$ROOT_DIR/$relative_dir" ]] || return 0
  (cd "$ROOT_DIR" && find "$relative_dir" -type f -name "$name_pattern" \
    ! -name '.DS_Store' \
    ! -path '*/.build/*' \
    ! -path '*/DerivedData/*' \
    -print) >>"$output_file"
}

write_participating_source_list() {
  local output_file="$1"
  local unsorted_file
  unsorted_file="$output_file.unsorted"
  : >"$unsorted_file"

  append_lock_file "$unsorted_file" "Package.swift"

  append_lock_tree "$unsorted_file" "Sources/WeiBei/App"
  append_lock_tree "$unsorted_file" "Sources/WeiBei/Views"
  append_lock_matches "$unsorted_file" "Sources/WeiBei/Support" "*RichAnswer*"
  append_lock_tree "$unsorted_file" "Sources/WeiBei/Resources"

  append_lock_tree "$unsorted_file" "Sources/WeiBeiCore/AgentResources"
  append_lock_matches "$unsorted_file" "Sources/WeiBeiCore" "*RichAnswer*"
  append_lock_file "$unsorted_file" "Sources/WeiBeiCore/PiAgentRuntime.swift"
  append_lock_file "$unsorted_file" "Sources/WeiBeiCore/StudyAgentRuntime.swift"

  append_lock_tree "$unsorted_file" "Sources/WeiBeiPiCheck"

  append_lock_file "$unsorted_file" "script/rich-answer-evidence-smoke.sh"
  append_lock_file "$unsorted_file" "script/rich-answer-visual-gate.swift"
  append_lock_file "$unsorted_file" "script/rich-answer-evidence-batch.sh"

  LC_ALL=C sort -u "$unsorted_file" >"$output_file"
  rm -f "$unsorted_file"
}

write_untracked_participating_source_list() {
  local named_list="$1"
  local output_file="$2"
  : >"$output_file"
  while IFS= read -r relative_path; do
    [[ -n "$relative_path" && -f "$ROOT_DIR/$relative_path" ]] || continue
    if ! git -C "$ROOT_DIR" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1; then
      printf '%s\n' "$relative_path" >>"$output_file"
    fi
  done <"$named_list"
}

append_current_manifest() {
  local manifest_file="$1"
  [[ -f "$manifest_file" ]] || return 0
  printf '%s\n' "$manifest_file" >>"$CURRENT_MANIFEST_LIST"
}

expected_screenshot_kinds() {
  local case_kind="$1"
  if [[ "$case_kind" == "rich" ]]; then
    printf 'before\nafter\n'
  else
    printf 'single\n'
  fi
}

manifest_expected_screenshot_kinds() {
  local manifest_file="$1"
  local case_kind="$2"
  local capture_kind
  if [[ -f "$manifest_file" ]] && jq -e 'has("captureKind") and ((.captureKind // "") != "")' "$manifest_file" >/dev/null; then
    capture_kind="$(jq -r '.captureKind // ""' "$manifest_file")"
    case "$capture_kind" in
      rich-interaction)
        printf 'before\nafter\n'
        ;;
      single)
        printf 'single\n'
        ;;
      *)
        return 2
        ;;
    esac
  else
    expected_screenshot_kinds "$case_kind"
  fi
}

write_baseline_state_json() {
  local output_file="$1"
  local tmp_dir
  local named_list
  local named_tsv
  local named_json
  local untracked_list
  local untracked_tsv
  local untracked_json
  local git_head
  local tracked_diff_sha
  local tracked_status_sha
  local source_lock_id
  local swift_version
  local xcode_path
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/weibei-baseline.XXXXXX")"
  named_list="$tmp_dir/named-files.txt"
  named_tsv="$tmp_dir/named-files.tsv"
  named_json="$tmp_dir/named-files.json"
  untracked_list="$tmp_dir/untracked-files.txt"
  untracked_tsv="$tmp_dir/untracked-files.tsv"
  untracked_json="$tmp_dir/untracked-files.json"
  write_participating_source_list "$named_list"
  write_untracked_participating_source_list "$named_list" "$untracked_list"
  hash_paths_json "$named_list" "$named_tsv" >"$named_json"
  hash_paths_json "$untracked_list" "$untracked_tsv" >"$untracked_json"
  git_head="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  source_lock_id="$(jq -n -S -c \
    --slurpfile named "$named_json" \
    --slurpfile untracked "$untracked_json" \
    --arg gitHead "$git_head" \
    '{gitHead: $gitHead, namedSourceFiles: $named[0], untrackedSourceFiles: $untracked[0]}' \
    | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  tracked_diff_sha="$(tracked_diff_sha256)"
  tracked_status_sha="$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=no 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  swift_version="$(swift --version 2>/dev/null | head -n 1 || printf 'unavailable')"
  xcode_path="$(xcode-select -p 2>/dev/null || printf 'unavailable')"
  jq -n \
    --slurpfile named "$named_json" \
    --slurpfile untracked "$untracked_json" \
    --arg gitHead "$git_head" \
    --arg sourceLockID "$source_lock_id" \
    --arg trackedDiffSHA256 "$tracked_diff_sha" \
    --arg trackedStatusSHA256 "$tracked_status_sha" \
    --arg runID "$RUN_ID" \
    --arg indexPath "$INDEX_PATH" \
    --arg runDir "$RUN_DIR" \
    --arg outputDir "$OUTPUT_DIR" \
    --arg smokeScript "$SMOKE_SCRIPT" \
    --arg smokeRunner "$SMOKE_RUNNER" \
    --arg visualScript "$VISUAL_SCRIPT" \
    --arg batchScript "$BATCH_SCRIPT" \
    --arg buildCacheDir "$BUILD_CACHE_DIR" \
    --arg swiftVersion "$swift_version" \
    --arg xcodePath "$xcode_path" \
    --arg jobs "$JOBS" \
    '{
      schemaVersion: 1,
      role: "rich-answer-first-round-source-lock",
      lockScope: {
        realApp: ["Sources/WeiBei/App", "Sources/WeiBei/Views"],
        richAnswerRenderer: ["Sources/WeiBeiCore/*RichAnswer*", "Sources/WeiBei/Support/*RichAnswer*", "Sources/WeiBei/Views"],
        webRuntimeAndResources: ["Sources/WeiBei/Resources"],
        promptsAndSkills: ["Sources/WeiBeiCore/AgentResources"],
        evidenceMatrix: ["Sources/WeiBeiPiCheck"],
        evidenceScripts: ["script/rich-answer-evidence-smoke.sh", "script/rich-answer-visual-gate.swift", "script/rich-answer-evidence-batch.sh"]
      },
      git: {
        head: $gitHead,
        trackedDiffSHA256: $trackedDiffSHA256,
        trackedStatusSHA256: $trackedStatusSHA256
      },
      sourceLockID: $sourceLockID,
      namedSourceFiles: $named[0],
      untrackedSourceFiles: $untracked[0],
      buildAndConfiguration: {
        runID: $runID,
        indexPath: $indexPath,
        runDir: $runDir,
        outputDir: $outputDir,
        smokeScript: $smokeScript,
        smokeRunner: $smokeRunner,
        visualScript: $visualScript,
        batchScript: $batchScript,
        buildCacheDir: $buildCacheDir,
        swiftVersion: $swiftVersion,
        xcodePath: $xcodePath,
        jobs: ($jobs | tonumber),
        existingBuild: true,
        suppressActivation: true
      }
    }' >"$output_file"
  rm -f "$named_list" "$named_tsv" "$named_json" "$untracked_list" "$untracked_tsv" "$untracked_json"
  rmdir "$tmp_dir" 2>/dev/null || true
}

baseline_id_for_state() {
  jq -S -c . "$1" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

write_or_validate_baseline_manifest() {
  local state_file
  local current_id
  local tmp_manifest
  mkdir -p "$FIRST_ROUND_ROOT"
  state_file="$(mktemp "${TMPDIR:-/tmp}/weibei-baseline-state.XXXXXX")"
  write_baseline_state_json "$state_file"
  current_id="$(baseline_id_for_state "$state_file")"
  if [[ -f "$BASELINE_MANIFEST" ]]; then
    BASELINE_ID="$(jq -r '.baselineID // ""' "$BASELINE_MANIFEST")"
    if [[ "$BASELINE_ID" != "$current_id" ]]; then
      echo "rich-answer baseline mismatch before batch: existing=$BASELINE_ID current=$current_id manifest=$BASELINE_MANIFEST" >&2
      rm -f "$state_file"
      return 80
    fi
    rm -f "$state_file"
    return 0
  fi
  BASELINE_ID="$current_id"
  tmp_manifest="$BASELINE_MANIFEST.tmp"
  jq \
    --arg baselineID "$BASELINE_ID" \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '. + {baselineID: $baselineID, generatedAt: $generatedAt}' \
    "$state_file" >"$tmp_manifest"
  mv "$tmp_manifest" "$BASELINE_MANIFEST"
  rm -f "$state_file"
}

assert_baseline_current() {
  local phase="${1:-batch}"
  local tmp_dir
  local named_list
  local named_tsv
  local named_json
  local untracked_list
  local untracked_tsv
  local untracked_json
  local expected_id
  local current_id
  local git_head
  local abort_tmp
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/weibei-source-lock.XXXXXX")"
  named_list="$tmp_dir/named-files.txt"
  named_tsv="$tmp_dir/named-files.tsv"
  named_json="$tmp_dir/named-files.json"
  untracked_list="$tmp_dir/untracked-files.txt"
  untracked_tsv="$tmp_dir/untracked-files.tsv"
  untracked_json="$tmp_dir/untracked-files.json"
  write_participating_source_list "$named_list"
  write_untracked_participating_source_list "$named_list" "$untracked_list"
  hash_paths_json "$named_list" "$named_tsv" >"$named_json"
  hash_paths_json "$untracked_list" "$untracked_tsv" >"$untracked_json"
  git_head="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  current_id="$(jq -n -S -c \
    --slurpfile named "$named_json" \
    --slurpfile untracked "$untracked_json" \
    --arg gitHead "$git_head" \
    '{gitHead: $gitHead, namedSourceFiles: $named[0], untrackedSourceFiles: $untracked[0]}' \
    | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  expected_id="$(jq -r '.sourceLockID // ""' "$BASELINE_MANIFEST")"
  rm -f "$named_list" "$named_tsv" "$named_json" "$untracked_list" "$untracked_tsv" "$untracked_json"
  rmdir "$tmp_dir" 2>/dev/null || true
  ASSERT_BASELINE_CURRENT_ID="$current_id"
  if [[ "$current_id" != "$expected_id" ]]; then
    abort_tmp="$SOURCE_LOCK_ABORT_FILE.tmp.${BASHPID:-$$}"
    jq -n \
      --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg phase "$phase" \
      --arg expectedSourceLockID "$expected_id" \
      --arg currentSourceLockID "$current_id" \
      --arg baselineID "$BASELINE_ID" \
      --arg baselineManifest "$BASELINE_MANIFEST" \
      '{generatedAt: $generatedAt, phase: $phase, expectedSourceLockID: $expectedSourceLockID, currentSourceLockID: $currentSourceLockID, baselineID: $baselineID, baselineManifestPath: $baselineManifest}' \
      >"$abort_tmp"
    mv "$abort_tmp" "$SOURCE_LOCK_ABORT_FILE"
    echo "rich-answer source state changed during $phase; sourceLock=$expected_id current=$current_id baseline=$BASELINE_ID. Stop instead of mixing evidence." >&2
    return 80
  fi
}

assert_batch_not_aborted() {
  if [[ -f "$SOURCE_LOCK_ABORT_FILE" ]]; then
    echo "rich-answer batch stopped because the source lock already changed: $SOURCE_LOCK_ABORT_FILE" >&2
    return 80
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index)
      INPUT_PATH="${2:?--index needs a path}"
      shift 2
      ;;
    --run)
      INPUT_PATH="${2:?--run needs a path}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:?--output-dir needs a path}"
      shift 2
      ;;
    --jobs)
      JOBS="${2:?--jobs needs 1 or 2}"
      shift 2
      ;;
    --resume)
      RESUME=1
      shift
      ;;
    --limit)
      LIMIT="${2:?--limit needs a number}"
      shift 2
      ;;
    --case)
      ONLY_CASE="${2:?--case needs a case id}"
      shift 2
      ;;
    --fixture-smoke)
      INPUT_PATH="$ROOT_DIR/Prototypes/RichAnswerEvidenceViewer/fixtures/demo-run/index.json"
      FIXTURE_SMOKE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$INPUT_PATH" ]]; then
  usage >&2
  exit 2
fi
if [[ "$JOBS" != "1" && "$JOBS" != "2" ]]; then
  echo "rich-answer screenshot batch rejects --jobs $JOBS; use 1 or 2 only." >&2
  exit 2
fi

if [[ -d "$INPUT_PATH" ]]; then
  RUN_DIR="$(abs_path "$INPUT_PATH")"
  INDEX_PATH="$RUN_DIR/index.json"
else
  INDEX_PATH="$(abs_path "$INPUT_PATH")"
  RUN_DIR="$(dirname "$INDEX_PATH")"
fi
if [[ ! -f "$INDEX_PATH" ]] && ! find "$RUN_DIR" -name record.json -type f -print -quit | grep -q .; then
  echo "index not found: $INDEX_PATH" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(abs_path "$OUTPUT_DIR")"
QUEUE_FILE="$OUTPUT_DIR/screenshot-queue.tsv"
BATCH_MANIFEST="$OUTPUT_DIR/screenshot-batch-manifest.json"
CURRENT_MANIFEST_LIST="$OUTPUT_DIR/.current-screenshot-manifests"
BUILD_CACHE_DIR="$OUTPUT_DIR/_app-cache"
trap cleanup_app_cache EXIT
FIRST_ROUND_ROOT="$OUTPUT_DIR/screenshots/repetition-1"
BASELINE_MANIFEST="$FIRST_ROUND_ROOT/baseline-manifest.json"
SOURCE_LOCK_ABORT_FILE="$OUTPUT_DIR/source-lock-abort.json"
BASELINE_ID=""
RUN_ID="$(basename "$RUN_DIR")"
if [[ -f "$INDEX_PATH" ]]; then
  RUN_ID="$(jq -r '.runID // .runId // input_filename | tostring' "$INDEX_PATH")"
fi

: >"$CURRENT_MANIFEST_LIST"
ensure_free_space "$OUTPUT_DIR" "batch setup"

if [[ -f "$INDEX_PATH" ]] && jq -e '.records and (.records | length > 0)' "$INDEX_PATH" >/dev/null; then
  jq -r '
    .records
    | to_entries[]
    | .key as $index
    | .value
    | [
        (.sequence // ($index + 1)),
        (.caseID // .caseId // .id // ("case-" + (($index + 1) | tostring))),
        (.repetition // 1),
        (.caseKind // .kind // "unknown"),
        (.status // "unknown"),
        (.recordPath // .record_path // ""),
        (.actualShape // "")
      ]
    | @tsv
  ' "$INDEX_PATH" >"$QUEUE_FILE"
else
  : >"$QUEUE_FILE"
  find "$RUN_DIR" -name record.json -type f | sort | while IFS= read -r record_file; do
    jq -r \
      --arg recordPath "${record_file#$RUN_DIR/}" \
      '[
        (.sequence // 0),
        (.caseSnapshot.id // "unknown-case"),
        (.repetition // 1),
        (.caseSnapshot.caseKind // "unknown"),
        (.status // "unknown"),
        $recordPath,
        (.shapeDecision.actualShape // "unknown")
      ] | @tsv' \
      "$record_file" >>"$QUEUE_FILE"
  done
fi

if [[ -n "$ONLY_CASE" ]]; then
  awk -F '\t' -v only="$ONLY_CASE" '$2 == only { print }' "$QUEUE_FILE" >"$QUEUE_FILE.filtered"
  mv "$QUEUE_FILE.filtered" "$QUEUE_FILE"
fi
if [[ -n "$LIMIT" ]]; then
  awk -v limit="$LIMIT" 'NR <= limit { print }' "$QUEUE_FILE" >"$QUEUE_FILE.limited"
  mv "$QUEUE_FILE.limited" "$QUEUE_FILE"
fi

QUEUE_TOTAL="$(awk -F '\t' 'NF >= 2 && $2 != "" { count += 1 } END { print count + 0 }' "$QUEUE_FILE")"
if [[ "$FIXTURE_SMOKE" != "1" && -z "$LIMIT" && -z "$ONLY_CASE" ]]; then
  UNIQUE_CASES="$(awk -F '\t' 'NF >= 3 && $2 != "" { cases[$2] = 1 } END { print length(cases) + 0 }' "$QUEUE_FILE")"
  OBSERVED_REPETITIONS="$(awk -F '\t' 'NF >= 3 && $3 != "" { reps[$3] = 1 } END { for (rep in reps) print rep }' "$QUEUE_FILE" | sort -n | paste -sd, -)"
  if [[ "$UNIQUE_CASES" != "56" ]] \
    || ! { [[ "$QUEUE_TOTAL" == "56" && "$OBSERVED_REPETITIONS" == "1" ]] \
      || [[ "$QUEUE_TOTAL" == "168" && "$OBSERVED_REPETITIONS" == "2,3,4" ]] \
      || [[ "$QUEUE_TOTAL" == "224" && "$OBSERVED_REPETITIONS" == "1,2,3,4" ]]; }; then
    echo "rich-answer screenshot batch requires first-round, stability-only, or full evidence queue: got total=$QUEUE_TOTAL uniqueCases=$UNIQUE_CASES repetitions=$OBSERVED_REPETITIONS; expected total=56 repetitions=1, total=168 repetitions=2,3,4, or total=224 repetitions=1,2,3,4, always with uniqueCases=56." >&2
    exit 2
  fi
fi
write_or_validate_baseline_manifest

annotate_manifest() {
  local manifest_file="$1"
  local sequence="$2"
  local case_id="$3"
  local repetition="$4"
  local case_kind="$5"
  local record_path="$6"
  local record_abs="$7"
  local pre_source_lock_id="${8:-}"
  local post_source_lock_id="${9:-}"
  local pre_verified_at="${10:-}"
  local post_verified_at="${11:-}"
  local tmp_file
  local record_sha=""
  local overview_path=""
  local before_path=""
  local after_path=""
  local single_path=""
  local overview_sha=""
  local before_sha=""
  local after_sha=""
  local single_sha=""
  local overview_bytes=""
  local before_bytes=""
  local after_bytes=""
  local single_bytes=""

  [[ -f "$manifest_file" ]] || return 0
  if [[ -f "$record_abs" ]]; then
    record_sha="$(sha256_file "$record_abs")"
  fi
  overview_path="$(jq -r '.screenshotEvidence.overview.path // .screenshots.overview // ""' "$manifest_file" 2>/dev/null || true)"
  before_path="$(jq -r '.screenshotEvidence.before.path // .screenshots.before // ""' "$manifest_file" 2>/dev/null || true)"
  after_path="$(jq -r '.screenshotEvidence.after.path // .screenshots.after // ""' "$manifest_file" 2>/dev/null || true)"
  single_path="$(jq -r '.screenshotEvidence.single.path // .screenshots.single // ""' "$manifest_file" 2>/dev/null || true)"
  if [[ -n "$overview_path" && -f "$overview_path" ]]; then overview_sha="$(sha256_file "$overview_path")"; overview_bytes="$(file_size_bytes "$overview_path")"; fi
  if [[ -n "$before_path" && -f "$before_path" ]]; then before_sha="$(sha256_file "$before_path")"; before_bytes="$(file_size_bytes "$before_path")"; fi
  if [[ -n "$after_path" && -f "$after_path" ]]; then after_sha="$(sha256_file "$after_path")"; after_bytes="$(file_size_bytes "$after_path")"; fi
  if [[ -n "$single_path" && -f "$single_path" ]]; then single_sha="$(sha256_file "$single_path")"; single_bytes="$(file_size_bytes "$single_path")"; fi

  tmp_file="$manifest_file.tmp"
  jq \
    --arg sequence "$sequence" \
    --arg caseID "$case_id" \
    --arg repetition "$repetition" \
    --arg caseKind "$case_kind" \
    --arg recordPath "$record_path" \
    --arg recordSHA256 "$record_sha" \
    --arg baselineID "$BASELINE_ID" \
    --arg baselineManifest "$BASELINE_MANIFEST" \
    --arg preSourceLockID "$pre_source_lock_id" \
    --arg postSourceLockID "$post_source_lock_id" \
    --arg preVerifiedAt "$pre_verified_at" \
    --arg postVerifiedAt "$post_verified_at" \
    --arg overviewPath "$overview_path" \
    --arg beforeSHA256 "$before_sha" \
    --arg afterSHA256 "$after_sha" \
    --arg singleSHA256 "$single_sha" \
    --arg overviewSHA256 "$overview_sha" \
    --arg overviewBytes "$overview_bytes" \
    --arg beforeBytes "$before_bytes" \
    --arg afterBytes "$after_bytes" \
    --arg singleBytes "$single_bytes" \
    '. + {
      sequence: ($sequence | tonumber? // $sequence),
      caseID: $caseID,
      repetition: ($repetition | tonumber? // $repetition),
      caseKind: $caseKind,
      baselineID: $baselineID,
      baselineManifestPath: $baselineManifest,
      recordPath: $recordPath,
      recordSHA256: (if $recordSHA256 == "" then null else $recordSHA256 end),
      baselineChecks: {
        beforeCase: {sourceLockID: $preSourceLockID, verifiedAt: $preVerifiedAt},
        afterCase: {sourceLockID: $postSourceLockID, verifiedAt: $postVerifiedAt}
      },
      screenshotSHA256: {
        overview: (if $overviewSHA256 == "" then null else $overviewSHA256 end),
        before: (if $beforeSHA256 == "" then null else $beforeSHA256 end),
        after: (if $afterSHA256 == "" then null else $afterSHA256 end),
        single: (if $singleSHA256 == "" then null else $singleSHA256 end)
      },
      screenshotEvidence: {
        overview: (if $overviewSHA256 == "" or $overviewPath == "" then null else {path: $overviewPath, sha256: $overviewSHA256, bytes: ($overviewBytes | tonumber)} end),
        before: (if $beforeSHA256 == "" then null else {path: (.screenshots.before // .screenshotEvidence.before.path), sha256: $beforeSHA256, bytes: ($beforeBytes | tonumber)} end),
        after: (if $afterSHA256 == "" then null else {path: (.screenshots.after // .screenshotEvidence.after.path), sha256: $afterSHA256, bytes: ($afterBytes | tonumber)} end),
        single: (if $singleSHA256 == "" then null else {path: (.screenshots.single // .screenshotEvidence.single.path), sha256: $singleSHA256, bytes: ($singleBytes | tonumber)} end)
      },
      reviewStatus: (.reviewStatus // "pending-user-acceptance")
    }' "$manifest_file" >"$tmp_file"
  mv "$tmp_file" "$manifest_file"
}

manifest_complete_for_resume() {
  local manifest_file="$1"
  local case_id="$2"
  local repetition="$3"
  local case_kind="$4"
  local record_path="$5"
  local record_abs="$6"
  local record_sha
  local kind
  local screenshot_path
  local expected_sha
  local expected_bytes
  local actual_sha
  local actual_bytes
  local expected_source_lock_id
  local expected_kinds_file

  [[ -f "$manifest_file" && -f "$record_abs" ]] || return 1
  record_sha="$(sha256_file "$record_abs")"
  expected_source_lock_id="$(jq -r '.sourceLockID // ""' "$BASELINE_MANIFEST")"
  jq -e \
    --arg caseID "$case_id" \
    --arg repetition "$repetition" \
    --arg caseKind "$case_kind" \
    --arg recordPath "$record_path" \
    --arg recordSHA256 "$record_sha" \
    --arg baselineID "$BASELINE_ID" \
    --arg sourceLockID "$expected_source_lock_id" \
    '.status == "succeeded"
      and .captureStatus == "succeeded"
      and .qualityGate.status == "pass"
      and ((.reviewStatus // "") != "")
      and .caseID == $caseID
      and ((.repetition | tostring) == $repetition)
      and .caseKind == $caseKind
      and .baselineID == $baselineID
      and (.baselineChecks.beforeCase.sourceLockID // "") == $sourceLockID
      and (.baselineChecks.afterCase.sourceLockID // "") == $sourceLockID
      and .recordPath == $recordPath
      and .recordSHA256 == $recordSHA256' "$manifest_file" >/dev/null || return 1

  expected_kinds_file="$(mktemp "${TMPDIR:-/tmp}/weibei-expected-screenshot-kinds.XXXXXX")"
  if ! manifest_expected_screenshot_kinds "$manifest_file" "$case_kind" >"$expected_kinds_file"; then
    rm -f "$expected_kinds_file"
    return 1
  fi
  while IFS= read -r kind; do
    screenshot_path="$(jq -r --arg kind "$kind" '.screenshotEvidence[$kind].path // .screenshots[$kind] // ""' "$manifest_file")"
    expected_sha="$(jq -r --arg kind "$kind" '.screenshotEvidence[$kind].sha256 // .screenshotSHA256[$kind] // ""' "$manifest_file")"
    expected_bytes="$(jq -r --arg kind "$kind" '.screenshotEvidence[$kind].bytes // ""' "$manifest_file")"
    [[ -n "$screenshot_path" && -f "$screenshot_path" && -n "$expected_sha" ]] || { rm -f "$expected_kinds_file"; return 1; }
    actual_sha="$(sha256_file "$screenshot_path")"
    [[ "$actual_sha" == "$expected_sha" ]] || { rm -f "$expected_kinds_file"; return 1; }
    if [[ -n "$expected_bytes" && "$expected_bytes" != "null" ]]; then
      actual_bytes="$(file_size_bytes "$screenshot_path")"
      [[ "$actual_bytes" == "$expected_bytes" ]] || { rm -f "$expected_kinds_file"; return 1; }
    fi
  done <"$expected_kinds_file"
  rm -f "$expected_kinds_file"
  if jq -e '(.screenshotEvidence.overview.path // .screenshots.overview // "") != ""' "$manifest_file" >/dev/null; then
    kind="overview"
    screenshot_path="$(jq -r --arg kind "$kind" '.screenshotEvidence[$kind].path // .screenshots[$kind] // ""' "$manifest_file")"
    expected_sha="$(jq -r --arg kind "$kind" '.screenshotEvidence[$kind].sha256 // .screenshotSHA256[$kind] // ""' "$manifest_file")"
    expected_bytes="$(jq -r --arg kind "$kind" '.screenshotEvidence[$kind].bytes // ""' "$manifest_file")"
    [[ -n "$screenshot_path" && -f "$screenshot_path" && -n "$expected_sha" ]] || return 1
    actual_sha="$(sha256_file "$screenshot_path")"
    [[ "$actual_sha" == "$expected_sha" ]] || return 1
    if [[ -n "$expected_bytes" && "$expected_bytes" != "null" ]]; then
      actual_bytes="$(file_size_bytes "$screenshot_path")"
      [[ "$actual_bytes" == "$expected_bytes" ]] || return 1
    fi
  fi
  return 0
}

run_one() {
  local sequence="$1"
  local case_id="$2"
  local repetition="$3"
  local case_kind="$4"
  local status="$5"
  local record_path="$6"
  local actual_shape="$7"
  local safe_case
  local safe_rep
  local case_root
  local case_output
  local record_abs
  local manifest_file
  local existing_manifest
  local run_status=0
  local pre_source_lock_id=""
  local post_source_lock_id=""
  local pre_verified_at=""
  local post_verified_at=""

  ensure_free_space "$OUTPUT_DIR" "case $case_id"
  assert_batch_not_aborted
  assert_baseline_current "before case $case_id repetition=$repetition"
  pre_source_lock_id="$ASSERT_BASELINE_CURRENT_ID"
  pre_verified_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  safe_case="$(sanitize_name "$case_id")"
  [[ -n "$safe_case" ]] || safe_case="case-$sequence"
  safe_rep="$(sanitize_name "$repetition")"
  [[ -n "$safe_rep" ]] || safe_rep="1"
  case_root="$OUTPUT_DIR/screenshots/repetition-$safe_rep/$safe_case"
  case_output="$case_root"

  if [[ "$record_path" = /* ]]; then
    record_abs="$record_path"
  else
    record_abs="$RUN_DIR/$record_path"
  fi

  mkdir -p "$(dirname "$case_root")"
  if [[ "$RESUME" == "1" && -d "$case_root" ]]; then
    while IFS= read -r existing_manifest; do
      if manifest_complete_for_resume "$existing_manifest" "$case_id" "$repetition" "$case_kind" "$record_path" "$record_abs"; then
        append_current_manifest "$existing_manifest"
        echo "skip(resume): $case_id repetition=$repetition"
        return 0
      fi
    done < <(find "$case_root" -name screenshot-manifest.json -type f 2>/dev/null | sort)
  fi
  local attempt_suffix
  attempt_suffix="$(date -u +%Y%m%dT%H%M%SZ)-${BASHPID:-$$}-$RANDOM"
  if [[ -e "$case_output/screenshot-manifest.json" ]]; then
    case_output="$case_root/attempt-$attempt_suffix"
  elif [[ -d "$case_root" ]] && [[ -n "$(find "$case_root" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]]; then
    case_output="$case_root/attempt-$attempt_suffix"
  fi
  mkdir -p "$case_output"
  manifest_file="$case_output/screenshot-manifest.json"

  if [[ ! -f "$record_abs" ]]; then
    jq -n \
      --arg caseID "$case_id" \
      --arg caseKind "$case_kind" \
      --arg repetition "$repetition" \
      --arg recordPath "$record_path" \
      --arg outputDir "$case_output" \
      --arg baselineID "$BASELINE_ID" \
      --arg baselineManifest "$BASELINE_MANIFEST" \
      --arg failureReason "record file not found: $record_abs" \
      '{generatedAt: (now | todateiso8601), script: "rich-answer-evidence-batch.sh", status: "failed", captureStatus: "failed", failureReason: $failureReason, caseID: $caseID, caseKind: $caseKind, repetition: ($repetition | tonumber? // $repetition), baselineID: $baselineID, baselineManifestPath: $baselineManifest, recordPath: $recordPath, outputDir: $outputDir, screenshots: {}, screenshotSHA256: {}, screenshotEvidence: {}, qualityGate: null, reviewStatus: "pending-user-acceptance"}' \
      >"$manifest_file"
    append_current_manifest "$manifest_file"
    return 20
  fi

  echo "capture: $case_id repetition=$repetition kind=$case_kind status=$status shape=$actual_shape"
  set +e
  RICH_ANSWER_EVIDENCE_DIR="$case_output" \
    RICH_ANSWER_EVIDENCE_PRESERVE_OUTPUT=1 \
    RICH_ANSWER_EVIDENCE_BUILD_CACHE_DIR="$BUILD_CACHE_DIR" \
    RICH_ANSWER_EVIDENCE_USE_EXISTING_BUILD=1 \
    WEIBEI_SUPPRESS_ACTIVATION=1 \
      "$SMOKE_RUNNER" \
        --replay "$record_abs" \
        --output-dir "$case_output" \
        --case-id "$case_id" \
        --case-kind "$case_kind" \
        --record-path "$record_path" \
        >"$case_output/run.log" 2>&1
  run_status=$?
  set -e
  assert_baseline_current "after case $case_id repetition=$repetition"
  post_source_lock_id="$ASSERT_BASELINE_CURRENT_ID"
  post_verified_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -f "$manifest_file" ]]; then
    annotate_manifest "$manifest_file" "$sequence" "$case_id" "$repetition" "$case_kind" "$record_path" "$record_abs" "$pre_source_lock_id" "$post_source_lock_id" "$pre_verified_at" "$post_verified_at"
    append_current_manifest "$manifest_file"
  fi
  return "$run_status"
}

export ROOT_DIR SMOKE_SCRIPT SMOKE_RUNNER VISUAL_SCRIPT BATCH_SCRIPT OUTPUT_DIR RUN_DIR INDEX_PATH RUN_ID RESUME BUILD_CACHE_DIR MIN_FREE_KB CURRENT_MANIFEST_LIST FIRST_ROUND_ROOT BASELINE_MANIFEST BASELINE_ID SOURCE_LOCK_ABORT_FILE ASSERT_BASELINE_CURRENT_ID
export -f available_free_kb ensure_free_space sanitize_name sha256_file file_size_bytes tracked_diff_sha256 hash_paths_json append_lock_file append_lock_tree append_lock_matches write_participating_source_list write_untracked_participating_source_list append_current_manifest expected_screenshot_kinds manifest_expected_screenshot_kinds write_baseline_state_json baseline_id_for_state assert_baseline_current assert_batch_not_aborted annotate_manifest manifest_complete_for_resume run_one

SOURCE_LOCK_ABORTED=0
while IFS=$'\t' read -r sequence case_id repetition case_kind status record_path actual_shape; do
  [[ -n "${case_id:-}" ]] || continue
  if ! assert_batch_not_aborted; then
    SOURCE_LOCK_ABORTED=1
    break
  fi
  while [[ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$JOBS" ]]; do
    if ! assert_batch_not_aborted; then
      SOURCE_LOCK_ABORTED=1
      break 2
    fi
    sleep 0.5
  done
  if ! assert_batch_not_aborted; then
    SOURCE_LOCK_ABORTED=1
    break
  fi
  run_one "$sequence" "$case_id" "$repetition" "$case_kind" "$status" "$record_path" "$actual_shape" &
done <"$QUEUE_FILE"

batch_status=0
if [[ "$SOURCE_LOCK_ABORTED" == "1" ]]; then
  batch_status=1
fi
for pid in $(jobs -pr); do
  if ! wait "$pid"; then
    batch_status=1
  fi
done
if [[ -f "$SOURCE_LOCK_ABORT_FILE" ]]; then
  batch_status=1
fi

manifest_files=()
while IFS= read -r manifest_file; do
  [[ -f "$manifest_file" ]] || continue
  manifest_files+=("$manifest_file")
done < <(sort -u "$CURRENT_MANIFEST_LIST")

quarantine_unregistered_case_artifacts() {
  local manifest_file="$1"
  local case_dir
  local partial_dir
  local listed_file
  local path
  local basename
  case_dir="$(dirname "$manifest_file")"
  partial_dir="$case_dir/_partial-unregistered"
  listed_file="$case_dir/.registered-screenshot-paths"
  jq -r '
    [
      .screenshots.before?,
      .screenshots.after?,
      .screenshots.single?,
      .screenshots.overview?
    ]
    | map(select(. != null and . != ""))
    | .[]
  ' "$manifest_file" >"$listed_file"
  for path in "$case_dir/overview.png" "$case_dir/before.png" "$case_dir/after.png" "$case_dir/single.png" "$case_dir/app-owned-initial.png"; do
    [[ -e "$path" ]] || continue
    if ! grep -Fxq "$path" "$listed_file"; then
      mkdir -p "$partial_dir"
      basename="$(basename "$path")"
      mv "$path" "$partial_dir/$basename"
      cat >"$partial_dir/README.txt" <<EOF
These files were captured before the rich-answer evidence run completed or were not registered in screenshot-manifest.json.
They must not be counted as acceptance evidence.
EOF
    fi
  done
  rm -f "$listed_file"
}

if [[ "${#manifest_files[@]}" -gt 0 ]]; then
  for manifest_file in "${manifest_files[@]}"; do
    quarantine_unregistered_case_artifacts "$manifest_file"
  done
fi

if [[ "${#manifest_files[@]}" -gt 0 ]]; then
  SOURCE_LOCK_ABORT_JSON="null"
  if [[ -f "$SOURCE_LOCK_ABORT_FILE" ]]; then
    SOURCE_LOCK_ABORT_JSON="$(jq -c . "$SOURCE_LOCK_ABORT_FILE")"
  fi
  jq -s \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg runID "$RUN_ID" \
    --arg indexPath "$INDEX_PATH" \
    --arg runDir "$RUN_DIR" \
    --arg outputDir "$OUTPUT_DIR" \
    --arg baselineID "$BASELINE_ID" \
    --arg baselineManifest "$BASELINE_MANIFEST" \
    --arg jobs "$JOBS" \
    --arg resume "$RESUME" \
    --arg expectedRecords "$QUEUE_TOTAL" \
    --argjson sourceLockAbort "$SOURCE_LOCK_ABORT_JSON" \
    '
      def hasUsableCaptureKind($record): ($record | has("captureKind")) and (($record.captureKind // "") != "");
      def expectedKindsFromCase($record): if $record.caseKind == "rich" then ["before", "after"] else ["single"] end;
      def expectedKinds($record):
        if hasUsableCaptureKind($record) then
          if $record.captureKind == "rich-interaction" then ["before", "after"]
          elif $record.captureKind == "single" then ["single"]
          else []
          end
        else expectedKindsFromCase($record)
        end;
      def captureKindValid($record):
        (hasUsableCaptureKind($record) | not) or ($record.captureKind == "rich-interaction" or $record.captureKind == "single");
      def verifiedImageCount($record):
        [expectedKinds($record)[] as $kind
          | ($record.screenshotEvidence[$kind] // {}) as $evidence
          | select(
              (($evidence.path // $record.screenshots[$kind] // "") != "")
              and (($evidence.sha256 // $record.screenshotSHA256[$kind] // "") | test("^[0-9a-f]{64}$"))
              and (($evidence.bytes // 0) > 0)
            )]
        | length;
      def expectedImageCount:
        ([.[] | expectedKinds(.) | length] | add // 0);
      def overviewValid($record):
        (($record.screenshotEvidence.overview.path // $record.screenshots.overview // "") == "")
        or (($record.screenshotEvidence.overview.sha256 // $record.screenshotSHA256.overview // "") != "" and ($record.screenshotEvidence.overview.bytes // 0) > 0);
    {
      generatedAt: $generatedAt,
      script: "rich-answer-evidence-batch.sh",
      status: (if
        $sourceLockAbort == null
        and
        length == ($expectedRecords | tonumber)
        and all(.[]; captureKindValid(.))
        and (([.[] | verifiedImageCount(.)] | add // 0) >= expectedImageCount)
        and all(.[]; overviewValid(.))
        and all(.[]; .baselineID == $baselineID)
        and all(.[]; .status == "succeeded" and .captureStatus == "succeeded" and (.qualityGate.status == "pass" or .qualityGate.status == "warn") and ((.reviewStatus // "") != ""))
        then "succeeded" else "failed" end),
      runID: $runID,
      indexPath: $indexPath,
      runDir: $runDir,
      outputDir: $outputDir,
      baselineID: $baselineID,
      baselineManifestPath: $baselineManifest,
      sourceLockAbort: $sourceLockAbort,
      jobs: ($jobs | tonumber),
      resume: ($resume == "1"),
      expectedRecords: ($expectedRecords | tonumber),
      expectedScreenshotImages: expectedImageCount,
      total: length,
      succeeded: ([.[] | select(.status == "succeeded")] | length),
      failed: ([.[] | select(.status != "succeeded")] | length),
      visualPassed: ([.[] | select(.qualityGate.status == "pass")] | length),
      visualWarned: ([.[] | select(.qualityGate.status == "warn")] | length),
      visualFailed: ([.[] | select((.qualityGate.status // "fail") == "fail")] | length),
      verifiedScreenshotImages: ([.[] | verifiedImageCount(.)] | add // 0),
      reviewStatus: "pending-user-acceptance",
      records: .
    }' "${manifest_files[@]}" >"$BATCH_MANIFEST"
  if ! jq -e '.status == "succeeded"' "$BATCH_MANIFEST" >/dev/null; then
    batch_status=1
  fi
else
  SOURCE_LOCK_ABORT_JSON="null"
  if [[ -f "$SOURCE_LOCK_ABORT_FILE" ]]; then
    SOURCE_LOCK_ABORT_JSON="$(jq -c . "$SOURCE_LOCK_ABORT_FILE")"
  fi
  jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg runID "$RUN_ID" \
    --arg indexPath "$INDEX_PATH" \
    --arg runDir "$RUN_DIR" \
    --arg outputDir "$OUTPUT_DIR" \
    --arg baselineID "$BASELINE_ID" \
    --arg baselineManifest "$BASELINE_MANIFEST" \
    --argjson sourceLockAbort "$SOURCE_LOCK_ABORT_JSON" \
    '{generatedAt: $generatedAt, script: "rich-answer-evidence-batch.sh", status: "failed", failureReason: "no screenshot manifests generated", runID: $runID, indexPath: $indexPath, runDir: $runDir, outputDir: $outputDir, baselineID: $baselineID, baselineManifestPath: $baselineManifest, sourceLockAbort: $sourceLockAbort, total: 0, succeeded: 0, failed: 0, records: []}' \
    >"$BATCH_MANIFEST"
  batch_status=1
fi

echo "rich_answer_screenshot_batch_dir=$OUTPUT_DIR"
echo "rich_answer_screenshot_batch_manifest=$BATCH_MANIFEST"
jq '{status,total,expectedRecords,succeeded,failed,verifiedScreenshotImages,expectedScreenshotImages,visualPassed,visualWarned,visualFailed,jobs,runID,baselineID,reviewStatus}' "$BATCH_MANIFEST"
exit "$batch_status"
