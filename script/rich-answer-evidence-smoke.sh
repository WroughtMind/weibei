#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO="rich-answer-preview"
REPLAY_ARTIFACT=""
CASE_ID=""
CASE_KIND=""
RECORD_PATH=""
SINGLE_SHOT="auto"
CLOBBER_OUTPUT="${RICH_ANSWER_EVIDENCE_CLOBBER_OUTPUT:-0}"
OUTPUT_DIR="${RICH_ANSWER_EVIDENCE_DIR:-${TMPDIR:-/tmp}/weibei-rich-answer-evidence-smoke-$(date +%Y%m%d-%H%M%S)}"
CONFIGURATION="${RICH_ANSWER_EVIDENCE_CONFIGURATION:-debug}"
PRODUCT_NAME="WeiBei"
APP_DISPLAY_NAME="魏碑"
BUNDLE_ID="com.changfenhuang.weibei.evidence-smoke"
APP_BUNDLE="$OUTPUT_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
WORKSPACE_DIR="$OUTPUT_DIR/workspace"
APP_STDOUT="$OUTPUT_DIR/app-stdout.log"
APP_STDERR="$OUTPUT_DIR/app-stderr.log"
AX_HELPER="$OUTPUT_DIR/rich-answer-ax-helper.swift"
AX_BINARY="$OUTPUT_DIR/rich-answer-ax-helper"
WINDOW_ID_FILE="$OUTPUT_DIR/window-id.txt"
OVERVIEW_SCREENSHOT="$OUTPUT_DIR/overview.png"
BEFORE_SCREENSHOT="$OUTPUT_DIR/before.png"
AFTER_SCREENSHOT="$OUTPUT_DIR/after.png"
SINGLE_SCREENSHOT="$OUTPUT_DIR/single.png"
AX_BEFORE="$OUTPUT_DIR/ax-before.txt"
AX_AFTER="$OUTPUT_DIR/ax-after.txt"
ACTION_RESULT="$OUTPUT_DIR/action-result.txt"
ACTION_ERROR="$OUTPUT_DIR/ax-action.err"
SCREENSHOT_ERROR="$OUTPUT_DIR/screencapture.err"
MANIFEST_JSON="$OUTPUT_DIR/screenshot-manifest.json"
PARTIAL_DIR="$OUTPUT_DIR/_partial-unregistered"
QUALITY_GATE_JSON="$OUTPUT_DIR/quality-gate.json"
VISUAL_GATE_SOURCE="$ROOT_DIR/script/rich-answer-visual-gate.swift"
VISUAL_GATE_BINARY="$OUTPUT_DIR/rich-answer-visual-gate"
AX_HELPER_CACHE_DIR="${RICH_ANSWER_EVIDENCE_AX_HELPER_CACHE_DIR:-}"
MIN_FREE_KB="${RICH_ANSWER_MIN_FREE_KB:-20971520}"
MANUAL_REVIEW_HOLD_SECONDS="${RICH_ANSWER_EVIDENCE_MANUAL_REVIEW_HOLD_SECONDS:-0}"
SWIFT_SDKROOT="${RICH_ANSWER_SWIFT_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
SWIFT_CLANG_MODULE_CACHE_DIR="${RICH_ANSWER_SWIFT_CLANG_MODULE_CACHE_DIR:-/private/tmp/weibei-clang-module-cache}"
SWIFTPM_MODULE_CACHE_DIR="${RICH_ANSWER_SWIFTPM_MODULE_CACHE_DIR:-/private/tmp/weibei-swiftpm-module-cache}"
APP_PID=""
WINDOW_ID=""
MANIFEST_WRITTEN=0
LAUNCHED_APP_PID=""
BUILD_SOURCE_FINGERPRINT=""
APP_BUNDLE_TREE_SHA256=""

usage() {
  cat <<'USAGE'
usage:
  script/rich-answer-evidence-smoke.sh [scenario]
  script/rich-answer-evidence-smoke.sh --replay <record-or-reply-json> --output-dir <dir> [--case-id id] [--case-kind kind]

options:
  --scenario <name>      Run an existing WeiBei verification scenario.
  --replay <path>        Replay one evidence record/reply through WEIBEI_VERIFY_RICH_ANSWER_REPLAY.
  --output-dir <dir>     Unique screenshot output directory for this case.
  --case-id <id>         Case id written to screenshot-manifest.json.
  --case-kind <kind>     rich, text-only, degradation, or invalid-protocol.
  --record-path <path>   Record path to backlink from screenshot-manifest.json.
  --single-shot          Capture only one screenshot and skip AX interaction.
  --clobber-output       Explicitly delete and recreate a prior output directory.
  --help                 Show this message.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO="${2:?--scenario needs a value}"
      shift 2
      ;;
    --replay)
      REPLAY_ARTIFACT="${2:?--replay needs a path}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:?--output-dir needs a path}"
      shift 2
      ;;
    --case-id)
      CASE_ID="${2:?--case-id needs a value}"
      shift 2
      ;;
    --case-kind)
      CASE_KIND="${2:?--case-kind needs a value}"
      shift 2
      ;;
    --record-path)
      RECORD_PATH="${2:?--record-path needs a value}"
      shift 2
      ;;
    --single-shot)
      SINGLE_SHOT="1"
      shift
      ;;
    --clobber-output)
      CLOBBER_OUTPUT="1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      SCENARIO="$1"
      shift
      ;;
  esac
done

if [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="$PWD/$OUTPUT_DIR"
fi

APP_BUNDLE="$OUTPUT_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
WORKSPACE_DIR="$OUTPUT_DIR/workspace"
APP_STDOUT="$OUTPUT_DIR/app-stdout.log"
APP_STDERR="$OUTPUT_DIR/app-stderr.log"
AX_HELPER="$OUTPUT_DIR/rich-answer-ax-helper.swift"
AX_BINARY="$OUTPUT_DIR/rich-answer-ax-helper"
WINDOW_ID_FILE="$OUTPUT_DIR/window-id.txt"
OVERVIEW_SCREENSHOT="$OUTPUT_DIR/overview.png"
BEFORE_SCREENSHOT="$OUTPUT_DIR/before.png"
AFTER_SCREENSHOT="$OUTPUT_DIR/after.png"
SINGLE_SCREENSHOT="$OUTPUT_DIR/single.png"
AX_BEFORE="$OUTPUT_DIR/ax-before.txt"
AX_AFTER="$OUTPUT_DIR/ax-after.txt"
ACTION_RESULT="$OUTPUT_DIR/action-result.txt"
ACTION_ERROR="$OUTPUT_DIR/ax-action.err"
SCREENSHOT_ERROR="$OUTPUT_DIR/screencapture.err"
MANIFEST_JSON="$OUTPUT_DIR/screenshot-manifest.json"
PARTIAL_DIR="$OUTPUT_DIR/_partial-unregistered"
QUALITY_GATE_JSON="$OUTPUT_DIR/quality-gate.json"
VISUAL_GATE_BINARY="$OUTPUT_DIR/rich-answer-visual-gate"
LAUNCH_HELPER_SOURCE="$OUTPUT_DIR/rich-answer-app-launcher.swift"
LAUNCH_HELPER_BINARY="$OUTPUT_DIR/rich-answer-app-launcher"
LAUNCH_ENVIRONMENT_JSON="$OUTPUT_DIR/launch-environment.json"
LAUNCH_PID_FILE="$OUTPUT_DIR/launch-pid.txt"
LAUNCH_ERROR_FILE="$OUTPUT_DIR/launch-error.log"
CAPTURE_CHANNEL_DIR="$WORKSPACE_DIR/capture-channel"
CAPTURE_REQUEST_FILE="$CAPTURE_CHANNEL_DIR/request.json"
CAPTURE_ACK_FILE="$CAPTURE_CHANNEL_DIR/ack.json"
ACTION_RECEIPT_WORKSPACE="$WORKSPACE_DIR/rich-answer-action-receipt.json"
ACTION_RECEIPT_ARCHIVE="$OUTPUT_DIR/action-receipt.json"
RENDERER_READY_FILE="$WORKSPACE_DIR/rich-answer-renderer-ready.txt"
OVERVIEW_CAPTURE_REQUEST="$OUTPUT_DIR/overview.request.json"
OVERVIEW_CAPTURE_ACK="$OUTPUT_DIR/overview.ack.json"
BEFORE_CAPTURE_REQUEST="$OUTPUT_DIR/before.request.json"
BEFORE_CAPTURE_ACK="$OUTPUT_DIR/before.ack.json"
AFTER_CAPTURE_REQUEST="$OUTPUT_DIR/after.request.json"
AFTER_CAPTURE_ACK="$OUTPUT_DIR/after.ack.json"
SINGLE_CAPTURE_REQUEST="$OUTPUT_DIR/single.request.json"
SINGLE_CAPTURE_ACK="$OUTPUT_DIR/single.ack.json"
CAPTURE_COUNTER=0

if [[ -n "${RICH_ANSWER_EVIDENCE_BUILD_CACHE_DIR:-}" ]]; then
  sdk_settings_path="$SWIFT_SDKROOT/SDKSettings.json"
  sdk_settings_signature="missing"
  if [[ -f "$sdk_settings_path" ]]; then
    sdk_settings_signature="$(stat -f '%m:%z' "$sdk_settings_path")"
  fi
  swift_cache_fingerprint="$({
    /usr/bin/swiftc --version
    printf '%s\n' "$SWIFT_SDKROOT" "$sdk_settings_signature"
  } | shasum -a 256 | awk '{print substr($1, 1, 16)}')"
  SWIFT_CLANG_MODULE_CACHE_DIR="$RICH_ANSWER_EVIDENCE_BUILD_CACHE_DIR/clang-module-cache-$swift_cache_fingerprint"
  SWIFTPM_MODULE_CACHE_DIR="$RICH_ANSWER_EVIDENCE_BUILD_CACHE_DIR/swiftpm-module-cache-$swift_cache_fingerprint"
  if [[ -z "$AX_HELPER_CACHE_DIR" ]]; then
    AX_HELPER_CACHE_DIR="$RICH_ANSWER_EVIDENCE_BUILD_CACHE_DIR/helper-cache-$swift_cache_fingerprint"
  fi
fi
mkdir -p "$SWIFT_CLANG_MODULE_CACHE_DIR" "$SWIFTPM_MODULE_CACHE_DIR"

validate_output_directory() {
  local output_parent
  local output_real
  local private_tmp_root
  local session_tmp_root

  output_parent="$(dirname "$OUTPUT_DIR")"
  if [[ ! -d "$output_parent" ]]; then
    echo "rich-answer evidence output parent must already exist: $output_parent" >&2
    exit 23
  fi
  output_real="$(cd "$output_parent" && pwd -P)/$(basename "$OUTPUT_DIR")"
  private_tmp_root="$(cd /private/tmp && pwd -P)"
  session_tmp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  case "$output_real" in
    "$private_tmp_root"/weibei-rich-answer-*|"$session_tmp_root"/weibei-rich-answer-*)
      ;;
    *)
      echo "rich-answer evidence output must stay inside a weibei-rich-answer-* temporary directory: $output_real" >&2
      exit 23
      ;;
  esac
  OUTPUT_DIR="$output_real"
}

validate_output_directory

if [[ -d "$OUTPUT_DIR" && -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  if [[ "$CLOBBER_OUTPUT" == "1" ]]; then
    rm -rf "$OUTPUT_DIR"
  elif [[ "${RICH_ANSWER_EVIDENCE_PRESERVE_OUTPUT:-0}" == "1" ]]; then
    unexpected_existing="$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 ! -name run.log -print -quit)"
    if [[ -n "$unexpected_existing" ]]; then
      echo "rich-answer evidence output already contains artifacts; choose a fresh directory or pass --clobber-output explicitly: $unexpected_existing" >&2
      exit 24
    fi
  else
    echo "rich-answer evidence output is not empty; refusing to overwrite prior evidence: $OUTPUT_DIR" >&2
    exit 24
  fi
fi
mkdir -p "$OUTPUT_DIR" "$WORKSPACE_DIR" "$CAPTURE_CHANNEL_DIR"

file_sha256() {
  local path="$1"
  if [[ -s "$path" ]]; then
    /usr/bin/shasum -a 256 "$path" | awk '{print $1}'
  fi
}

file_size_bytes() {
  local path="$1"
  if [[ -s "$path" ]]; then
    /usr/bin/stat -f '%z' "$path"
  fi
}

json_file_evidence() {
  local path="$1"
  if [[ -s "$path" ]]; then
    jq -n \
      --arg path "$path" \
      --arg sha256 "$(file_sha256 "$path")" \
      --arg bytes "$(file_size_bytes "$path")" \
      '{path: $path, sha256: $sha256, bytes: ($bytes | tonumber)}'
  else
    printf 'null\n'
  fi
}

source_input_fingerprint() {
  {
    printf 'configuration\t%s\n' "$CONFIGURATION"
    {
      find "$ROOT_DIR/Sources" "$ROOT_DIR/Prototypes/RichAnswerWebRuntime/src" -type f -print 2>/dev/null || true
      for path in \
        "$ROOT_DIR/Package.swift" \
        "$ROOT_DIR/Package.resolved" \
        "$ROOT_DIR/package-lock.json" \
        "$ROOT_DIR/Prototypes/RichAnswerWebRuntime/package.json" \
        "$ROOT_DIR/Prototypes/RichAnswerWebRuntime/tsconfig.json" \
        "$ROOT_DIR/Vendor/PiRuntime/manifest.json" \
        "$ROOT_DIR/script/rich-answer-evidence-smoke.sh" \
        "$ROOT_DIR/script/rich-answer-visual-gate.swift"; do
        [[ -f "$path" ]] && printf '%s\n' "$path"
      done
    } | LC_ALL=C sort -u | while IFS= read -r path; do
      printf '%s\t%s\n' "${path#"$ROOT_DIR"/}" "$(file_sha256 "$path")"
    done
  } | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

bundle_tree_sha256() {
  local bundle="$1"
  (
    cd "$bundle"
    find . -type f -print | LC_ALL=C sort | while IFS= read -r path; do
      printf '%s\t%s\n' "$path" "$(file_sha256 "$path")"
    done
  ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

json_manifest() {
  local status="$1"
  local failure_reason="$2"
  local capture_kind="$3"
  local replay_marker="$WORKSPACE_DIR/rich-answer-replay-verified.txt"
  local scenario_marker="$WORKSPACE_DIR/rich-answer-verified.txt"
  local error_marker="$WORKSPACE_DIR/rich-answer-replay-error.txt"
  local marker_path=""
  local quality_gate="null"
  local capture_status="failed"
  local before_sha256=""
  local after_sha256=""
  local single_sha256=""
  local overview_sha256=""
  local before_bytes=""
  local after_bytes=""
  local single_bytes=""
  local overview_bytes=""
  local overview_request_evidence="null"
  local overview_ack_evidence="null"
  local before_request_evidence="null"
  local before_ack_evidence="null"
  local after_request_evidence="null"
  local after_ack_evidence="null"
  local single_request_evidence="null"
  local single_ack_evidence="null"
  local action_receipt_evidence="null"
  if [[ -s "$replay_marker" ]]; then
    marker_path="$replay_marker"
  elif [[ -s "$scenario_marker" ]]; then
    marker_path="$scenario_marker"
  elif [[ -s "$error_marker" ]]; then
    marker_path="$error_marker"
  fi
  if [[ -s "$QUALITY_GATE_JSON" ]] && jq -e . "$QUALITY_GATE_JSON" >/dev/null 2>&1; then
    quality_gate="$(cat "$QUALITY_GATE_JSON")"
  fi
  if [[ "$capture_kind" == "rich-interaction" && -s "$OVERVIEW_SCREENSHOT" && -s "$BEFORE_SCREENSHOT" && -s "$AFTER_SCREENSHOT" ]]; then
    capture_status="succeeded"
  elif [[ "$capture_kind" == "single" && -s "$SINGLE_SCREENSHOT" ]]; then
    capture_status="succeeded"
  fi
  overview_sha256="$(file_sha256 "$OVERVIEW_SCREENSHOT")"
  before_sha256="$(file_sha256 "$BEFORE_SCREENSHOT")"
  after_sha256="$(file_sha256 "$AFTER_SCREENSHOT")"
  single_sha256="$(file_sha256 "$SINGLE_SCREENSHOT")"
  overview_bytes="$(file_size_bytes "$OVERVIEW_SCREENSHOT")"
  before_bytes="$(file_size_bytes "$BEFORE_SCREENSHOT")"
  after_bytes="$(file_size_bytes "$AFTER_SCREENSHOT")"
  single_bytes="$(file_size_bytes "$SINGLE_SCREENSHOT")"
  overview_request_evidence="$(json_file_evidence "$OVERVIEW_CAPTURE_REQUEST")"
  overview_ack_evidence="$(json_file_evidence "$OVERVIEW_CAPTURE_ACK")"
  before_request_evidence="$(json_file_evidence "$BEFORE_CAPTURE_REQUEST")"
  before_ack_evidence="$(json_file_evidence "$BEFORE_CAPTURE_ACK")"
  after_request_evidence="$(json_file_evidence "$AFTER_CAPTURE_REQUEST")"
  after_ack_evidence="$(json_file_evidence "$AFTER_CAPTURE_ACK")"
  single_request_evidence="$(json_file_evidence "$SINGLE_CAPTURE_REQUEST")"
  single_ack_evidence="$(json_file_evidence "$SINGLE_CAPTURE_ACK")"
  action_receipt_evidence="$(json_file_evidence "$ACTION_RECEIPT_ARCHIVE")"

  jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg script "rich-answer-evidence-smoke.sh" \
    --arg status "$status" \
    --arg captureStatus "$capture_status" \
    --arg failureReason "$failure_reason" \
    --arg captureKind "$capture_kind" \
    --arg scenario "$SCENARIO" \
    --arg replayArtifact "$REPLAY_ARTIFACT" \
    --arg caseID "$CASE_ID" \
    --arg caseKind "$CASE_KIND" \
    --arg recordPath "$RECORD_PATH" \
    --arg outputDir "$OUTPUT_DIR" \
    --arg workspaceDir "$WORKSPACE_DIR" \
    --arg appPid "${APP_PID:-}" \
    --arg windowID "${WINDOW_ID:-}" \
    --arg overview "$OVERVIEW_SCREENSHOT" \
    --arg before "$BEFORE_SCREENSHOT" \
    --arg after "$AFTER_SCREENSHOT" \
    --arg single "$SINGLE_SCREENSHOT" \
    --arg overviewSha256 "$overview_sha256" \
    --arg beforeSha256 "$before_sha256" \
    --arg afterSha256 "$after_sha256" \
    --arg singleSha256 "$single_sha256" \
    --arg overviewBytes "$overview_bytes" \
    --arg beforeBytes "$before_bytes" \
    --arg afterBytes "$after_bytes" \
    --arg singleBytes "$single_bytes" \
    --arg axBefore "$AX_BEFORE" \
    --arg axAfter "$AX_AFTER" \
    --arg action "$ACTION_RESULT" \
    --arg actionError "$ACTION_ERROR" \
    --arg marker "$marker_path" \
    --arg stdout "$APP_STDOUT" \
    --arg stderr "$APP_STDERR" \
    --arg captureChannel "$CAPTURE_CHANNEL_DIR" \
    --arg buildSourceFingerprint "$BUILD_SOURCE_FINGERPRINT" \
    --arg appBundleTreeSHA256 "$APP_BUNDLE_TREE_SHA256" \
    --argjson overviewRequestEvidence "$overview_request_evidence" \
    --argjson overviewAckEvidence "$overview_ack_evidence" \
    --argjson beforeRequestEvidence "$before_request_evidence" \
    --argjson beforeAckEvidence "$before_ack_evidence" \
    --argjson afterRequestEvidence "$after_request_evidence" \
    --argjson afterAckEvidence "$after_ack_evidence" \
    --argjson singleRequestEvidence "$single_request_evidence" \
    --argjson singleAckEvidence "$single_ack_evidence" \
    --argjson actionReceiptEvidence "$action_receipt_evidence" \
    --argjson qualityGate "$quality_gate" \
    '{
      generatedAt: $generatedAt,
      script: $script,
      status: $status,
      captureStatus: $captureStatus,
      failureReason: (if $failureReason == "" then null else $failureReason end),
      captureKind: $captureKind,
      scenario: $scenario,
      replayArtifact: (if $replayArtifact == "" then null else $replayArtifact end),
      caseID: (if $caseID == "" then null else $caseID end),
      caseKind: (if $caseKind == "" then null else $caseKind end),
      recordPath: (if $recordPath == "" then null else $recordPath end),
      outputDir: $outputDir,
      workspaceDir: $workspaceDir,
      appPid: (if $appPid == "" then null else ($appPid | tonumber? // $appPid) end),
      windowID: (if $windowID == "" then null else ($windowID | tonumber? // $windowID) end),
      screenshots: {
        overview: (if $captureKind == "rich-interaction" then $overview else null end),
        before: (if $captureKind == "rich-interaction" then $before else null end),
        after: (if $captureKind == "rich-interaction" then $after else null end),
        single: (if $captureKind == "single" then $single else null end)
      },
      screenshotEvidence: {
        overview: (if $captureKind == "rich-interaction" and $overviewSha256 != "" then {
          path: $overview,
          sha256: $overviewSha256,
          bytes: ($overviewBytes | tonumber)
        } else null end),
        before: (if $captureKind == "rich-interaction" and $beforeSha256 != "" then {
          path: $before,
          sha256: $beforeSha256,
          bytes: ($beforeBytes | tonumber)
        } else null end),
        after: (if $captureKind == "rich-interaction" and $afterSha256 != "" then {
          path: $after,
          sha256: $afterSha256,
          bytes: ($afterBytes | tonumber)
        } else null end),
        single: (if $captureKind == "single" and $singleSha256 != "" then {
          path: $single,
          sha256: $singleSha256,
          bytes: ($singleBytes | tonumber)
        } else null end)
      },
      ax: {
        before: (if $captureKind == "rich-interaction" then $axBefore else null end),
        after: (if $captureKind == "rich-interaction" then $axAfter else null end),
        action: (if $captureKind == "rich-interaction" then $action else null end),
        actionError: $actionError,
        appReceipt: (if $captureKind == "rich-interaction" then $actionReceiptEvidence else null end)
      },
      verificationMarker: (if $marker == "" then null else $marker end),
      logs: {
        stdout: $stdout,
        stderr: $stderr
      },
      captureSource: "application-owned-content-view",
      captureChannel: $captureChannel,
      buildEvidence: {
        sourceFingerprint: (if $buildSourceFingerprint == "" then null else $buildSourceFingerprint end),
        appBundleTreeSHA256: (if $appBundleTreeSHA256 == "" then null else $appBundleTreeSHA256 end),
        codeSignatureVerified: ($appBundleTreeSHA256 != "")
      },
      captureReceipts: {
        overview: {request: $overviewRequestEvidence, acknowledgement: $overviewAckEvidence},
        before: {request: $beforeRequestEvidence, acknowledgement: $beforeAckEvidence},
        after: {request: $afterRequestEvidence, acknowledgement: $afterAckEvidence},
        single: {request: $singleRequestEvidence, acknowledgement: $singleAckEvidence}
      },
      qualityGate: $qualityGate,
      reviewStatus: "pending-user-acceptance"
    }' >"$MANIFEST_JSON"
  MANIFEST_WRITTEN=1
}

quarantine_partial_artifacts() {
  local path
  local moved=0
  for path in \
    "$OVERVIEW_SCREENSHOT" \
    "$BEFORE_SCREENSHOT" \
    "$AFTER_SCREENSHOT" \
    "$SINGLE_SCREENSHOT" \
    "$OUTPUT_DIR/app-owned-initial.png" \
    "$AX_BEFORE" \
    "$AX_AFTER" \
    "$ACTION_RESULT" \
    "$ACTION_RECEIPT_ARCHIVE"; do
    if [[ -e "$path" ]]; then
      mkdir -p "$PARTIAL_DIR"
      mv "$path" "$PARTIAL_DIR/$(basename "$path")"
      moved=1
    fi
  done
  if [[ "$moved" == "1" ]]; then
    cat >"$PARTIAL_DIR/README.txt" <<EOF
These files were captured before the rich-answer evidence run completed.
They are intentionally outside the manifest screenshot paths and must not be counted as acceptance evidence.
EOF
  fi
}

cleanup() {
  local code=$?
  if [[ "$MANIFEST_WRITTEN" != "1" && -d "$OUTPUT_DIR" ]]; then
    quarantine_partial_artifacts || true
    json_manifest "failed" "script exited with code $code" "unknown" || true
  fi
  if [[ -n "${APP_PID:-}" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${LAUNCHED_APP_PID:-}" && "${LAUNCHED_APP_PID:-}" != "${APP_PID:-}" ]]; then
    kill "$LAUNCHED_APP_PID" >/dev/null 2>&1 || true
  fi
  if [[ "${RICH_ANSWER_EVIDENCE_PRESERVE_APP_BUNDLE:-0}" != "1" && -d "$APP_BUNDLE" ]]; then
    rm -rf "$APP_BUNDLE"
  fi
}
trap cleanup EXIT

fail_with_manifest() {
  local code="$1"
  local message="$2"
  local capture_kind="${3:-unknown}"
  echo "$message" >&2
  json_manifest "failed" "$message" "$capture_kind"
  exit "$code"
}

available_free_kb() {
  df -Pk "$1" | awk 'NR == 2 { print $4 }'
}

require_free_space() {
  local phase="$1"
  local available
  available="$(available_free_kb "$OUTPUT_DIR")"
  if [[ ! "$available" =~ ^[0-9]+$ ]]; then
    fail_with_manifest 28 "rich-answer evidence smoke cannot read free disk space during $phase: $OUTPUT_DIR" "unknown"
  fi
  if (( available < MIN_FREE_KB )); then
    fail_with_manifest 29 "rich-answer evidence smoke stopped during $phase: ${available} KiB free, requires at least ${MIN_FREE_KB} KiB." "unknown"
  fi
}

cat >"$AX_HELPER" <<'SWIFT'
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func copyAttribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard result == .success else { return nil }
    return value as AnyObject?
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String {
    copyAttribute(element, name) as? String ?? ""
}

func doubleAttribute(_ element: AXUIElement, _ name: String) -> Double? {
    if let number = copyAttribute(element, name) as? NSNumber {
        return number.doubleValue
    }
    if let string = copyAttribute(element, name) as? String {
        return Double(string)
    }
    return nil
}

func children(of element: AXUIElement) -> [AXUIElement] {
    elementArrayAttribute(element, kAXChildrenAttribute as String)
}

func elementArrayAttribute(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
    var valueCount: CFIndex = 0
    guard AXUIElementGetAttributeValueCount(element, name as CFString, &valueCount) == .success,
          valueCount > 0 else {
        return []
    }
    var values: CFArray?
    guard AXUIElementCopyAttributeValues(element, name as CFString, 0, valueCount, &values) == .success,
          let array = values else {
        return []
    }
    return (0..<CFArrayGetCount(array)).compactMap { index in
        guard let pointer = CFArrayGetValueAtIndex(array, index) else { return nil }
        let candidate = Unmanaged<AXUIElement>.fromOpaque(pointer).takeUnretainedValue()
        guard CFGetTypeID(candidate) == AXUIElementGetTypeID() else { return nil }
        return candidate
    }
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = copyAttribute(element, kAXPositionAttribute as String),
          let sizeValue = copyAttribute(element, kAXSizeAttribute as String) else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
}

func setSize(_ size: CGSize, of element: AXUIElement) -> AXError {
    var mutableSize = size
    guard let value = AXValueCreate(.cgSize, &mutableSize) else { return .failure }
    return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
}

func elementSummary(_ element: AXUIElement) -> String {
    let role = stringAttribute(element, kAXRoleAttribute as String)
    let identifier = stringAttribute(element, "AXIdentifier")
    let title = stringAttribute(element, kAXTitleAttribute as String)
    let description = stringAttribute(element, kAXDescriptionAttribute as String)
    let value = copyAttribute(element, kAXValueAttribute as String).map { "\($0)" } ?? ""
    let frameText: String
    if let frame = frame(of: element) {
        frameText = " frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))"
    } else {
        frameText = ""
    }
    return "role=\(role) id=\(identifier) title=\(title) desc=\(description) value=\(value)\(frameText)"
}

func matches(_ element: AXUIElement, query: String) -> Bool {
    let fields = [
        stringAttribute(element, "AXIdentifier"),
        stringAttribute(element, kAXTitleAttribute as String),
        stringAttribute(element, kAXDescriptionAttribute as String),
        stringAttribute(element, kAXHelpAttribute as String),
        "\(copyAttribute(element, kAXValueAttribute as String) ?? "" as NSString)",
    ]
    return fields.contains { $0.localizedCaseInsensitiveContains(query) }
}

func isInteractive(_ element: AXUIElement) -> Bool {
    let role = stringAttribute(element, kAXRoleAttribute as String)
    return [
        kAXButtonRole,
        kAXCheckBoxRole,
        kAXRadioButtonRole,
        kAXSliderRole,
        kAXTextFieldRole,
        kAXPopUpButtonRole,
        kAXMenuButtonRole,
        kAXScrollBarRole,
    ].contains(role)
}

func isUsefulDumpElement(_ element: AXUIElement) -> Bool {
    if isInteractive(element) { return true }
    let role = stringAttribute(element, kAXRoleAttribute as String)
    if role == kAXWindowRole { return true }
    let identifier = stringAttribute(element, "AXIdentifier")
    if [
        "stable-document-slot-reader",
        "stable-document-slot-agent",
        "persistent-pane-reader",
        "persistent-pane-agent",
    ].contains(identifier) { return true }
    let summary = elementSummary(element)
    return summary.localizedCaseInsensitiveContains("rich-answer")
        || summary.localizedCaseInsensitiveContains("富回答")
        || summary.localizedCaseInsensitiveContains("展开完整视觉体验")
        || summary.localizedCaseInsensitiveContains("下一步")
        || summary.localizedCaseInsensitiveContains("上一步")
        || summary.localizedCaseInsensitiveContains("滑块")
        || summary.localizedCaseInsensitiveContains("slider")
}

func walk(_ root: AXUIElement, limit: Int = 1600) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue = [root]
    var cursor = 0
    while cursor < queue.count && result.count < limit {
        let element = queue[cursor]
        cursor += 1
        result.append(element)
        queue.append(contentsOf: children(of: element))
    }
    return result
}

func targetCandidates(in root: AXUIElement, query: String) -> [AXUIElement] {
    let allowsExpansionButton = query.localizedCaseInsensitiveContains("展开")
        || query.localizedCaseInsensitiveContains("expand")
        || query.localizedCaseInsensitiveContains("visual")
    let candidates = walk(root).filter {
        matches($0, query: query)
            && (allowsExpansionButton || !elementSummary($0).localizedCaseInsensitiveContains("展开完整视觉体验"))
    }
    let interactive = candidates.filter(isInteractive)
    return interactive.isEmpty ? candidates : interactive
}

func focusedWindow(in app: AXUIElement) -> AXUIElement {
    func isWindow(_ element: AXUIElement) -> Bool {
        stringAttribute(element, kAXRoleAttribute as String) == kAXWindowRole
    }
    func isPlausibleWindowRoot(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as String)
        if role == kAXApplicationRole || role == kAXMenuBarRole || role == kAXMenuRole || role == kAXMenuItemRole {
            return false
        }
        guard let frame = frame(of: element) else { return false }
        return frame.width >= 600 && frame.height >= 400
    }
    if let window = copyAttribute(app, kAXFocusedWindowAttribute as String) as! AXUIElement?, isWindow(window) {
        return window
    }
    if let focused = copyAttribute(app, kAXFocusedWindowAttribute as String) as! AXUIElement?, isPlausibleWindowRoot(focused) {
        return focused
    }
    if let window = copyAttribute(app, kAXMainWindowAttribute as String) as! AXUIElement?, isWindow(window) {
        return window
    }
    if let window = copyAttribute(app, kAXMainWindowAttribute as String) as! AXUIElement?, isPlausibleWindowRoot(window) {
        return window
    }
    let windows = elementArrayAttribute(app, kAXWindowsAttribute as String)
    if !windows.isEmpty {
        if let window = windows.first(where: { isWindow($0) }) {
            return window
        }
        if let window = windows.first(where: { isPlausibleWindowRoot($0) }) {
            return window
        }
        if let window = windows.first {
            return window
        }
    }
    let descendants = walk(app, limit: 1200)
    if let window = descendants.first(where: { isWindow($0) }) {
        return window
    }
    if let window = descendants.first(where: { isPlausibleWindowRoot($0) }) {
        return window
    }
    var attributeNames: CFArray?
    let namesResult = AXUIElementCopyAttributeNames(app, &attributeNames)
    let namesCount = (attributeNames as? [String])?.count ?? 0
    let windowElements = elementArrayAttribute(app, kAXWindowsAttribute as String)
    let childElements = elementArrayAttribute(app, kAXChildrenAttribute as String)
    let windowCount = windowElements.count
    let childCount = childElements.count
    let role = stringAttribute(app, kAXRoleAttribute as String)
    let hidden = copyAttribute(app, kAXHiddenAttribute as String).map { String(describing: $0) } ?? "nil"
    let frontmost = copyAttribute(app, kAXFrontmostAttribute as String).map { String(describing: $0) } ?? "nil"
    let windowSummaries = windowElements
        .map(elementSummary)
        .joined(separator: " || ")
    let childSummaries = childElements
        .map(elementSummary)
        .joined(separator: " || ")
    FileHandle.standardError.write(Data((
        "AX app diagnostics: trusted=\(AXIsProcessTrusted()) role=\(role) attributes=\(namesCount) namesResult=\(namesResult.rawValue) windows=\(windowCount) children=\(childCount) hidden=\(hidden) frontmost=\(frontmost) windowSummaries=[\(windowSummaries)] childSummaries=[\(childSummaries)]\n"
    ).utf8))
    fail("AX helper could not find a WeiBei window", code: 4)
}

func windowID(for pid: pid_t) -> UInt32 {
    let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in windows {
        guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue == Int(pid) else { continue }
        guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { continue }
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? NSNumber,
              let height = bounds["Height"] as? NSNumber,
              width.doubleValue >= 600,
              height.doubleValue >= 400,
              let id = window[kCGWindowNumber as String] as? UInt32 else { continue }
        return id
    }
    fail("AX helper could not find a capturable WeiBei window", code: 5)
}

func imageHasVisibleContent(_ image: CGImage) -> Bool {
    let sampleWidth = max(1, min(80, image.width))
    let sampleHeight = max(1, min(60, image.height))
    let bytesPerRow = sampleWidth * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * sampleHeight)
    guard let context = CGContext(
        data: &pixels,
        width: sampleWidth,
        height: sampleHeight,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }
    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

    var visible = 0
    var black = 0
    var transparent = 0
    let sampleCount = sampleWidth * sampleHeight
    for index in 0..<sampleCount {
        let offset = index * 4
        let red = pixels[offset]
        let green = pixels[offset + 1]
        let blue = pixels[offset + 2]
        let alpha = pixels[offset + 3]
        if alpha < 13 {
            transparent += 1
        }
        if max(red, green, blue) > 20 {
            visible += 1
        }
        if alpha >= 13, max(red, green, blue) < 9 {
            black += 1
        }
    }
    let total = Double(sampleCount)
    return Double(visible) / total >= 0.02
        && Double(black) / total <= 0.12
        && Double(transparent) / total <= 0.005
}

func screenCaptureImage(pid: pid_t, windowID: UInt32) -> CGImage {
    if let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(windowID),
        [.boundsIgnoreFraming, .bestResolution]
    ), imageHasVisibleContent(image) {
        return image
    }

    let contentSemaphore = DispatchSemaphore(value: 0)
    var shareableContent: SCShareableContent?
    var shareableContentError: Error?
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, error in
        shareableContent = content
        shareableContentError = error
        contentSemaphore.signal()
    }
    guard contentSemaphore.wait(timeout: .now() + 15) == .success else {
        fail("ScreenCaptureKit timed out while finding the WeiBei window", code: 14)
    }
    if let shareableContentError {
        fail("ScreenCaptureKit could not list windows: \(shareableContentError.localizedDescription)", code: 15)
    }
    guard let window = shareableContent?.windows.first(where: {
        $0.windowID == CGWindowID(windowID)
            && $0.owningApplication?.processID == pid
            && $0.windowLayer == 0
    }) else {
        fail("ScreenCaptureKit could not match WeiBei window \(windowID)", code: 16)
    }

    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = SCStreamConfiguration()
    let pixelScale = max(CGFloat(filter.pointPixelScale), 1)
    configuration.width = max(1, Int(ceil(window.frame.width * pixelScale)))
    configuration.height = max(1, Int(ceil(window.frame.height * pixelScale)))
    configuration.scalesToFit = false
    configuration.preservesAspectRatio = true
    configuration.showsCursor = false
    configuration.ignoreShadowsSingleWindow = true
    configuration.captureResolution = .best

    let captureSemaphore = DispatchSemaphore(value: 0)
    var capturedImage: CGImage?
    var captureError: Error?
    SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
        capturedImage = image
        captureError = error
        captureSemaphore.signal()
    }
    guard captureSemaphore.wait(timeout: .now() + 15) == .success else {
        fail("ScreenCaptureKit timed out while capturing WeiBei window \(windowID)", code: 17)
    }
    if let captureError {
        fail("ScreenCaptureKit could not capture WeiBei window \(windowID): \(captureError.localizedDescription)", code: 18)
    }
    guard let capturedImage else {
        fail("ScreenCaptureKit returned no image for WeiBei window \(windowID)", code: 19)
    }
    return capturedImage
}

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]) else {
    fail("usage: rich-answer-ax-helper <pid> <ready|dump|window|capture|refresh|reveal|center|press|increment|set|activate> [query] [value]", code: 2)
}

let command = args[2]
let app = AXUIElementCreateApplication(pid)
let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
guard trusted else {
    fail("Accessibility permission is not granted to this terminal/Codex host", code: 3)
}

switch command {
case "ready":
    _ = focusedWindow(in: app)
    print("ready")
case "window":
    print(windowID(for: pid))
case "capture":
    guard args.count >= 4 else { fail("capture needs an output path", code: 2) }
    _ = focusedWindow(in: app)
    let id = windowID(for: pid)
    let image = screenCaptureImage(pid: pid, windowID: id)
    guard imageHasVisibleContent(image) else {
        fail("captured WeiBei window is empty, black, or transparent", code: 13)
    }
    let outputURL = URL(fileURLWithPath: args[3])
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
        fail("could not create PNG destination: \(outputURL.path)", code: 11)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("could not finalize PNG: \(outputURL.path)", code: 12)
    }
    print(id)
case "dump":
    let root = focusedWindow(in: app)
    let elements = walk(root).filter(isUsefulDumpElement)
    for element in elements.prefix(900) {
        print(elementSummary(element))
    }
case "refresh":
    let root = focusedWindow(in: app)
    guard let originalFrame = frame(of: root) else { fail("AX refresh could not read window frame", code: 20) }
    let expandedSize = CGSize(width: originalFrame.width + 1, height: originalFrame.height)
    guard setSize(expandedSize, of: root) == .success else { fail("AX refresh could not nudge window size", code: 21) }
    Thread.sleep(forTimeInterval: 0.08)
    guard setSize(originalFrame.size, of: root) == .success else { fail("AX refresh could not restore window size", code: 22) }
    Thread.sleep(forTimeInterval: 0.28)
    print(elementSummary(root))
case "reveal":
    guard args.count >= 4 else { fail("reveal needs a query", code: 2) }
    let query = args[3]
    let root = focusedWindow(in: app)
    guard let target = targetCandidates(in: root, query: query).first else {
        fail("AX reveal target not found: \(query)", code: 6)
    }
    let result = AXUIElementPerformAction(target, "AXScrollToVisible" as CFString)
    guard result == .success else { fail("AX reveal failed: \(result.rawValue)", code: 23) }
    Thread.sleep(forTimeInterval: 0.5)
    print(elementSummary(target))
case "center":
    guard args.count >= 4 else { fail("center needs a query", code: 2) }
    let query = args[3]
    let root = focusedWindow(in: app)
    let elements = walk(root)
    guard let target = targetCandidates(in: root, query: query).first,
          let initialTargetFrame = frame(of: target) else {
        fail("AX center target not found: \(query)", code: 6)
    }
    let scrollAreas = elements.compactMap { element -> (AXUIElement, CGRect)? in
        guard stringAttribute(element, kAXRoleAttribute as String) == kAXScrollAreaRole,
              let scrollFrame = frame(of: element),
              scrollFrame.minX <= initialTargetFrame.midX,
              initialTargetFrame.midX <= scrollFrame.maxX,
              scrollFrame.width >= initialTargetFrame.width * 0.72 else { return nil }
        return (element, scrollFrame)
    }
    guard let (scrollArea, viewportFrame) = scrollAreas.min(by: { $0.1.width < $1.1.width }),
          let rawScrollBar = copyAttribute(scrollArea, kAXVerticalScrollBarAttribute as String) else {
        fail("AX center could not find the target scroll area", code: 24)
    }
    let scrollBar = rawScrollBar as! AXUIElement
    guard let scrollBarFrame = frame(of: scrollBar),
          let currentValue = doubleAttribute(scrollBar, kAXValueAttribute as String) else {
        fail("AX center could not read the vertical scroll bar", code: 25)
    }
    let indicatorHeight = children(of: scrollBar)
        .first(where: { stringAttribute($0, kAXRoleAttribute as String) == "AXValueIndicator" })
        .flatMap { frame(of: $0)?.height }
    let scrollablePixels: CGFloat
    if let indicatorHeight, indicatorHeight > 1 {
        scrollablePixels = max(viewportFrame.height, viewportFrame.height * (scrollBarFrame.height / indicatorHeight - 1))
    } else {
        scrollablePixels = max(viewportFrame.height, 1)
    }
    let desiredMidY = viewportFrame.midY - min(42, initialTargetFrame.height * 0.12)
    let targetDelta = desiredMidY - initialTargetFrame.midY
    let minimumValue = doubleAttribute(scrollBar, kAXMinValueAttribute as String) ?? 0
    let maximumValue = doubleAttribute(scrollBar, kAXMaxValueAttribute as String) ?? 1
    let nextValue = min(max(currentValue - Double(targetDelta / scrollablePixels), minimumValue), maximumValue)
    let result = AXUIElementSetAttributeValue(scrollBar, kAXValueAttribute as CFString, NSNumber(value: nextValue))
    guard result == .success else { fail("AX center failed: \(result.rawValue)", code: 26) }
    Thread.sleep(forTimeInterval: 0.6)
    print("viewport=\(Int(viewportFrame.minX)),\(Int(viewportFrame.minY)),\(Int(viewportFrame.width)),\(Int(viewportFrame.height))")
    print("scroll=\(currentValue)->\(nextValue)")
    print(elementSummary(target))
case "press":
    guard args.count >= 4 else { fail("press needs a query", code: 2) }
    let query = args[3]
    let root = focusedWindow(in: app)
    guard let target = targetCandidates(in: root, query: query).first else {
        fail("AX press target not found: \(query)", code: 6)
    }
    let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
    guard result == .success else { fail("AX press failed: \(result.rawValue)", code: 7) }
    print(elementSummary(target))
case "increment":
    guard args.count >= 4 else { fail("increment needs a query", code: 2) }
    let query = args[3]
    let root = focusedWindow(in: app)
    guard let target = targetCandidates(in: root, query: query).first else {
        fail("AX increment target not found: \(query)", code: 6)
    }
    let before = doubleAttribute(target, kAXValueAttribute as String)
    let result = AXUIElementPerformAction(target, kAXIncrementAction as CFString)
    guard result == .success else { fail("AX increment failed: \(result.rawValue)", code: 7) }
    Thread.sleep(forTimeInterval: 0.25)
    let after = doubleAttribute(target, kAXValueAttribute as String)
    print("target=\(elementSummary(target))")
    print("before=\(before.map { String($0) } ?? "nil")")
    print("after=\(after.map { String($0) } ?? "nil")")
case "set":
    guard args.count >= 5, let value = Double(args[4]) else { fail("set needs a query and numeric value", code: 2) }
    let query = args[3]
    let root = focusedWindow(in: app)
    guard let target = targetCandidates(in: root, query: query).first else {
        fail("AX set target not found: \(query)", code: 6)
    }
    let before = doubleAttribute(target, kAXValueAttribute as String)
    let result = AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, NSNumber(value: value))
    guard result == .success else { fail("AX set value failed: \(result.rawValue)", code: 8) }
    Thread.sleep(forTimeInterval: 0.25)
    let after = doubleAttribute(target, kAXValueAttribute as String)
    print("target=\(elementSummary(target))")
    print("before=\(before.map { String($0) } ?? "nil")")
    print("after=\(after.map { String($0) } ?? "nil")")
case "activate":
    let result = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    guard result == .success else { fail("AX activate failed: \(result.rawValue)", code: 9) }
default:
    fail("unknown command: \(command)", code: 2)
}
SWIFT

build_app_bundle() {
  BUILD_SOURCE_FINGERPRINT="$(source_input_fingerprint)"

  package_app_from_build_dir() {
    local build_dir="$1"
    local build_binary="$build_dir/$PRODUCT_NAME"
    local pdf_text_worker="$build_dir/WeiBeiPDFTextWorker"
    local pi_runtime_dir
    pi_runtime_dir="$(
      cd "$ROOT_DIR"
      swift run WeiBeiDevTool prepare pi-runtime --format path
    )"

    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_HELPERS"
    cp "$build_binary" "$APP_BINARY"
    chmod +x "$APP_BINARY"
    if [[ -x "$pdf_text_worker" ]]; then
      cp "$pdf_text_worker" "$APP_HELPERS/WeiBeiPDFTextWorker"
      chmod +x "$APP_HELPERS/WeiBeiPDFTextWorker"
    fi
    for resource_bundle in "$build_dir/${PRODUCT_NAME}_${PRODUCT_NAME}.bundle" "$build_dir/${PRODUCT_NAME}_WeiBeiCore.bundle"; do
      [[ -d "$resource_bundle" ]] && cp -R "$resource_bundle" "$APP_RESOURCES/"
    done
    cp -R "$pi_runtime_dir" "$APP_RESOURCES/PiRuntime"
    printf '%s\n' "$BUILD_SOURCE_FINGERPRINT" >"$APP_RESOURCES/rich-answer-evidence-source.sha256"
    cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
    /usr/bin/xattr -cr "$APP_BUNDLE"
    if [[ -x "$APP_HELPERS/WeiBeiPDFTextWorker" ]]; then
      /usr/bin/codesign --force --sign - --timestamp=none "$APP_HELPERS/WeiBeiPDFTextWorker" >/dev/null
    fi
    /usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null
    /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  }

  if [[ "${RICH_ANSWER_EVIDENCE_USE_EXISTING_BUILD:-0}" == "1" ]]; then
    local existing_build_dir="$ROOT_DIR/.build/$CONFIGURATION"
    local existing_build_marker="$existing_build_dir/.weibei-rich-answer-evidence-source.sha256"
    if [[ -x "$existing_build_dir/$PRODUCT_NAME" ]] \
      && [[ -s "$existing_build_marker" ]] \
      && [[ "$(cat "$existing_build_marker")" == "$BUILD_SOURCE_FINGERPRINT" ]]; then
      package_app_from_build_dir "$existing_build_dir"
      return
    fi
  fi

  local cache_dir="${RICH_ANSWER_EVIDENCE_BUILD_CACHE_DIR:-}"
  local cached_app=""
  local cached_source_marker=""
  local cached_tree_marker=""
  restore_cached_app() {
    [[ -n "$cached_app" ]] || return 1
    [[ -x "$cached_app/Contents/MacOS/$PRODUCT_NAME" ]] || return 1
    [[ -s "$cached_source_marker" && -s "$cached_tree_marker" ]] || return 1
    [[ "$(cat "$cached_source_marker")" == "$BUILD_SOURCE_FINGERPRINT" ]] || return 1
    /usr/bin/codesign --verify --deep --strict "$cached_app" >/dev/null 2>&1 || return 1
    [[ "$(bundle_tree_sha256 "$cached_app")" == "$(cat "$cached_tree_marker")" ]] || return 1
    rm -rf "$APP_BUNDLE"
    cp -R "$cached_app" "$APP_BUNDLE"
    /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1 || return 1
    [[ "$(bundle_tree_sha256 "$APP_BUNDLE")" == "$(cat "$cached_tree_marker")" ]] || return 1
  }
  if [[ -n "$cache_dir" ]]; then
    cached_app="$cache_dir/$APP_DISPLAY_NAME.app"
    cached_source_marker="$cache_dir/$APP_DISPLAY_NAME.source.sha256"
    cached_tree_marker="$cache_dir/$APP_DISPLAY_NAME.tree.sha256"
    if restore_cached_app; then
      return
    fi
    mkdir -p "$cache_dir"
    local lock_dir="$cache_dir/.build.lock"
    while ! mkdir "$lock_dir" 2>/dev/null; do
      sleep 0.5
      if restore_cached_app; then
        return
      fi
    done
    trap 'rm -rf "$lock_dir"; cleanup' EXIT
  fi

  "$ROOT_DIR/Prototypes/RichAnswerWebRuntime/node_modules/.bin/tsc" -p "$ROOT_DIR/Prototypes/RichAnswerWebRuntime/tsconfig.json" --noEmit
  SDKROOT="$SWIFT_SDKROOT" \
  CLANG_MODULE_CACHE_PATH="$SWIFT_CLANG_MODULE_CACHE_DIR" \
  SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_MODULE_CACHE_DIR" \
    swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME"

  local build_dir
  build_dir="$(
    SDKROOT="$SWIFT_SDKROOT" \
    CLANG_MODULE_CACHE_PATH="$SWIFT_CLANG_MODULE_CACHE_DIR" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_MODULE_CACHE_DIR" \
      swift build -c "$CONFIGURATION" --show-bin-path
  )"
  printf '%s\n' "$BUILD_SOURCE_FINGERPRINT" >"$build_dir/.weibei-rich-answer-evidence-source.sha256"
  package_app_from_build_dir "$build_dir"

  if [[ -n "$cache_dir" ]]; then
    rm -rf "$cached_app"
    cp -R "$APP_BUNDLE" "$cached_app"
    /usr/bin/codesign --verify --deep --strict "$cached_app"
    printf '%s\n' "$BUILD_SOURCE_FINGERPRINT" >"$cached_source_marker"
    bundle_tree_sha256 "$cached_app" >"$cached_tree_marker"
    rm -rf "$cache_dir/.build.lock"
    trap cleanup EXIT
  fi
}

require_free_space "app build"
build_app_bundle
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
APP_BUNDLE_TREE_SHA256="$(bundle_tree_sha256 "$APP_BUNDLE")"
require_free_space "accessibility helper build"
build_ax_helper() {
  if [[ -n "$AX_HELPER_CACHE_DIR" ]]; then
    local cached_source="$AX_HELPER_CACHE_DIR/rich-answer-ax-helper.swift"
    local cached_binary="$AX_HELPER_CACHE_DIR/rich-answer-ax-helper"
    mkdir -p "$AX_HELPER_CACHE_DIR"
    if [[ -x "$cached_binary" && -f "$cached_source" ]] && cmp -s "$AX_HELPER" "$cached_source"; then
      cp "$cached_binary" "$AX_BINARY"
      return
    fi
    /usr/bin/swiftc -sdk "$SWIFT_SDKROOT" -module-cache-path "$SWIFT_CLANG_MODULE_CACHE_DIR" -Xfrontend -disable-availability-checking "$AX_HELPER" -framework ScreenCaptureKit -o "$AX_BINARY"
    cp "$AX_HELPER" "$cached_source"
    cp "$AX_BINARY" "$cached_binary"
    return
  fi
  /usr/bin/swiftc -sdk "$SWIFT_SDKROOT" -module-cache-path "$SWIFT_CLANG_MODULE_CACHE_DIR" -Xfrontend -disable-availability-checking "$AX_HELPER" -framework ScreenCaptureKit -o "$AX_BINARY"
}

build_ax_helper

require_free_space "visual quality gate build"
build_visual_gate() {
  if [[ -n "$AX_HELPER_CACHE_DIR" ]]; then
    local cached_source="$AX_HELPER_CACHE_DIR/rich-answer-visual-gate.swift"
    local cached_binary="$AX_HELPER_CACHE_DIR/rich-answer-visual-gate"
    mkdir -p "$AX_HELPER_CACHE_DIR"
    if [[ ! -x "$cached_binary" || ! -f "$cached_source" ]] || ! cmp -s "$VISUAL_GATE_SOURCE" "$cached_source"; then
      /usr/bin/swiftc -sdk "$SWIFT_SDKROOT" -module-cache-path "$SWIFT_CLANG_MODULE_CACHE_DIR" "$VISUAL_GATE_SOURCE" -framework AppKit -o "$cached_binary"
      cp "$VISUAL_GATE_SOURCE" "$cached_source"
    fi
    VISUAL_GATE_BINARY="$cached_binary"
    return
  fi
  /usr/bin/swiftc -sdk "$SWIFT_SDKROOT" -module-cache-path "$SWIFT_CLANG_MODULE_CACHE_DIR" "$VISUAL_GATE_SOURCE" -framework AppKit -o "$VISUAL_GATE_BINARY"
}

build_visual_gate

cat >"$LAUNCH_HELPER_SOURCE" <<'SWIFT'
import AppKit
import Foundation

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fail("usage: rich-answer-app-launcher <app-bundle> <environment-json>", code: 2)
}

let appURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
let environmentURL = URL(fileURLWithPath: arguments[2])
guard let environmentData = try? Data(contentsOf: environmentURL),
      let environment = try? JSONDecoder().decode([String: String].self, from: environmentData) else {
    fail("could not read launch environment JSON", code: 3)
}

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = false
configuration.addsToRecentItems = false
configuration.createsNewApplicationInstance = true
configuration.environment = environment

var result: Result<NSRunningApplication, Error>?
NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { application, error in
    if let application {
        result = .success(application)
    } else {
        result = .failure(error ?? CocoaError(.executableNotLoadable))
    }
}

let deadline = Date().addingTimeInterval(20)
while result == nil, Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}

guard let result else {
    fail("NSWorkspace launch timed out", code: 4)
}
switch result {
case let .success(application):
    print(application.processIdentifier)
case let .failure(error):
    fail("NSWorkspace launch failed: \(error.localizedDescription)", code: 5)
}
SWIFT

build_launch_helper() {
  if [[ -n "$AX_HELPER_CACHE_DIR" ]]; then
    local cached_source="$AX_HELPER_CACHE_DIR/rich-answer-app-launcher.swift"
    local cached_binary="$AX_HELPER_CACHE_DIR/rich-answer-app-launcher"
    mkdir -p "$AX_HELPER_CACHE_DIR"
    if [[ -x "$cached_binary" && -f "$cached_source" ]] && cmp -s "$LAUNCH_HELPER_SOURCE" "$cached_source"; then
      cp "$cached_binary" "$LAUNCH_HELPER_BINARY"
      return
    fi
    /usr/bin/swiftc -sdk "$SWIFT_SDKROOT" -module-cache-path "$SWIFT_CLANG_MODULE_CACHE_DIR" "$LAUNCH_HELPER_SOURCE" -framework AppKit -o "$LAUNCH_HELPER_BINARY"
    cp "$LAUNCH_HELPER_SOURCE" "$cached_source"
    cp "$LAUNCH_HELPER_BINARY" "$cached_binary"
    return
  fi
  /usr/bin/swiftc -sdk "$SWIFT_SDKROOT" -module-cache-path "$SWIFT_CLANG_MODULE_CACHE_DIR" "$LAUNCH_HELPER_SOURCE" -framework AppKit -o "$LAUNCH_HELPER_BINARY"
}

build_launch_helper

env_args=(
  WEIBEI_SUPPRESS_ACTIVATION=1
  WEIBEI_FORCE_OFFLINE_AGENT=1
  "WEIBEI_WORKSPACE_DIR=$WORKSPACE_DIR"
  "WEIBEI_VERIFY_CAPTURE_REQUEST_DIR=$CAPTURE_CHANNEL_DIR"
  "WEIBEI_VERIFY_CAPTURE_OUTPUT_DIR=$OUTPUT_DIR"
  "WEIBEI_VERIFY_CASE_ID=$CASE_ID"
  "WEIBEI_VERIFY_CASE_KIND=$CASE_KIND"
  "WEIBEI_VERIFY_RECORD_PATH=$RECORD_PATH"
)
if [[ -n "${WEIBEI_VERIFY_WINDOW_SIZE:-}" ]]; then
  env_args+=("WEIBEI_VERIFY_WINDOW_SIZE=$WEIBEI_VERIFY_WINDOW_SIZE")
fi
if [[ -n "${WEIBEI_VERIFY_AGENT_PANE_RATIO:-}" ]]; then
  env_args+=("WEIBEI_VERIFY_AGENT_PANE_RATIO=$WEIBEI_VERIFY_AGENT_PANE_RATIO")
fi
if [[ -n "${WEIBEI_VERIFY_RICH_ANSWER_CAPTURE_ANCHOR:-}" ]]; then
  env_args+=("WEIBEI_VERIFY_RICH_ANSWER_CAPTURE_ANCHOR=$WEIBEI_VERIFY_RICH_ANSWER_CAPTURE_ANCHOR")
fi
if [[ "${RICH_ANSWER_CAPTURE_LEGACY_INITIAL:-0}" == "1" ]]; then
  env_args+=("WEIBEI_VERIFY_CAPTURE_PATH=$OUTPUT_DIR/app-owned-initial.png")
fi
if [[ -n "$REPLAY_ARTIFACT" ]]; then
  env_args+=("WEIBEI_VERIFY_RICH_ANSWER_REPLAY=$REPLAY_ARTIFACT")
else
  env_args+=("WEIBEI_VERIFY_SCENARIO=$SCENARIO")
fi

printf '{}\n' >"$LAUNCH_ENVIRONMENT_JSON"
for entry in "${env_args[@]}"; do
  key="${entry%%=*}"
  value="${entry#*=}"
  jq --arg key "$key" --arg value "$value" '. + {($key): $value}' \
    "$LAUNCH_ENVIRONMENT_JSON" >"$LAUNCH_ENVIRONMENT_JSON.tmp"
  mv "$LAUNCH_ENVIRONMENT_JSON.tmp" "$LAUNCH_ENVIRONMENT_JSON"
done

: >"$APP_STDOUT"
: >"$APP_STDERR"
if ! "$LAUNCH_HELPER_BINARY" "$APP_BUNDLE" "$LAUNCH_ENVIRONMENT_JSON" >"$LAUNCH_PID_FILE" 2>"$LAUNCH_ERROR_FILE"; then
  cat "$LAUNCH_ERROR_FILE" >&2 || true
  fail_with_manifest 9 "rich-answer evidence smoke failed: signed app bundle could not launch through NSWorkspace" "unknown"
fi
APP_PID="$(tail -n 1 "$LAUNCH_PID_FILE" | tr -d '[:space:]')"
if [[ ! "$APP_PID" =~ ^[0-9]+$ ]] || ! kill -0 "$APP_PID" >/dev/null 2>&1; then
  cat "$LAUNCH_ERROR_FILE" >&2 || true
  fail_with_manifest 9 "rich-answer evidence smoke failed: NSWorkspace did not return a live WeiBei process" "unknown"
fi
printf 'WeiBei launched through signed NSWorkspace bundle; process output is detached by LaunchServices.\n' >"$APP_STDOUT"
LAUNCHED_APP_PID="$APP_PID"

refresh_app_pid() {
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    return 0
  fi
  local found_pid
  found_pid="$(
    /bin/ps -axo pid=,command= 2>/dev/null \
      | /usr/bin/awk -v binary="$APP_BINARY" 'index($0, binary) { print $1; exit }'
  )"
  if [[ -n "$found_pid" ]] && kill -0 "$found_pid" >/dev/null 2>&1; then
    APP_PID="$found_pid"
    return 0
  fi
  return 1
}

MARKER_FILE="$WORKSPACE_DIR/rich-answer-verified.txt"
if [[ -n "$REPLAY_ARTIFACT" ]]; then
  MARKER_FILE="$WORKSPACE_DIR/rich-answer-replay-verified.txt"
fi
ERROR_FILE="$WORKSPACE_DIR/rich-answer-replay-error.txt"

app_seen_dead=0
for _ in {1..120}; do
  if [[ -s "$MARKER_FILE" || -s "$ERROR_FILE" ]]; then
    break
  fi
  refresh_app_pid || app_seen_dead=1
  sleep 0.25
done

if [[ ! -s "$MARKER_FILE" && ! -s "$ERROR_FILE" ]]; then
  cat "$APP_STDERR" >&2 || true
  if [[ "$app_seen_dead" == "1" ]]; then
    fail_with_manifest 10 "rich-answer evidence smoke failed: WeiBei exited before replay marker" "unknown"
  fi
  fail_with_manifest 11 "rich-answer evidence smoke failed: verification marker missing" "unknown"
fi

for _ in {1..80}; do
  if ! refresh_app_pid; then
    cat "$APP_STDERR" >&2 || true
    fail_with_manifest 12 "rich-answer evidence smoke failed: WeiBei exited before a capturable window appeared" "unknown"
  fi
  if "$AX_BINARY" "$APP_PID" window >"$WINDOW_ID_FILE" 2>"$OUTPUT_DIR/ax-window.err"; then
    break
  fi
  sleep 0.25
done
if [[ ! -s "$WINDOW_ID_FILE" ]]; then
  cat "$OUTPUT_DIR/ax-window.err" >&2 || true
  fail_with_manifest 12 "rich-answer evidence smoke failed: capturable window missing" "unknown"
fi

WINDOW_ID="$(cat "$WINDOW_ID_FILE")"

capture_window() {
  require_free_space "window capture"
  local target="$1"
  local require_renderer_ready="${2:-0}"
  local request_id
  local request_tmp
  local attempt
  local actual_sha256
  local actual_bytes
  local capture_label
  local request_archive
  local ack_archive
  local require_panes=0

  if [[ -n "$REPLAY_ARTIFACT" && "$CASE_KIND" == "rich" ]]; then
    require_panes=1
  fi

  CAPTURE_COUNTER=$((CAPTURE_COUNTER + 1))
  capture_label="$(basename "$target" .png)"
  request_archive="$OUTPUT_DIR/$capture_label.request.json"
  ack_archive="$OUTPUT_DIR/$capture_label.ack.json"
  request_id="$$-$CAPTURE_COUNTER-$(date +%s)"
  request_tmp="$CAPTURE_REQUEST_FILE.tmp.$$"
  rm -f "$target" "$CAPTURE_ACK_FILE" "$request_tmp" "$request_archive" "$ack_archive"
  : >"$SCREENSHOT_ERROR"
  jq -n \
    --arg id "$request_id" \
    --arg capturePath "$target" \
    --arg stage "$capture_label" \
    '{id: $id, capturePath: $capturePath, stage: $stage}' >"$request_tmp"
  mv "$request_tmp" "$CAPTURE_REQUEST_FILE"
  cp "$CAPTURE_REQUEST_FILE" "$request_archive"

  for attempt in {1..120}; do
    if [[ -s "$CAPTURE_ACK_FILE" ]] \
      && jq -e --arg id "$request_id" '.id == $id' "$CAPTURE_ACK_FILE" >/dev/null 2>&1; then
      cp "$CAPTURE_ACK_FILE" "$ack_archive"
      if jq -e \
        --arg target "$target" \
        --arg stage "$capture_label" \
        --argjson requireReady "$require_renderer_ready" \
        --argjson requirePanes "$require_panes" \
        '.status == "succeeded"
          and .stage == $stage
          and .requestCapturePath == $target
          and .capturePath == $target
          and .actualPNG.path == $target
          and (.actualPNG.bytes | type == "number" and . > 0)
          and (.actualPNG.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
          and (($requireReady == 0) or (.renderReady.seen == true and (.renderReady.sha256 | test("^[0-9a-f]{64}$"))))
          and (($requirePanes == 0) or (
            .workspaceState.showReader == true
            and .workspaceState.showAgent == true
            and (.workspaceState.visiblePanes | index("reader") != null)
            and (.workspaceState.visiblePanes | index("agent") != null)
            and .captureWorkspaceState.stable == true
            and .captureWorkspaceState.start.showReader == true
            and .captureWorkspaceState.start.showAgent == true
            and .captureWorkspaceState.end.showReader == true
            and .captureWorkspaceState.end.showAgent == true
            and (.captureWorkspaceState.start.visiblePanes | index("reader") != null)
            and (.captureWorkspaceState.start.visiblePanes | index("agent") != null)
            and (.captureWorkspaceState.end.visiblePanes | index("reader") != null)
            and (.captureWorkspaceState.end.visiblePanes | index("agent") != null)
          ))' \
        "$CAPTURE_ACK_FILE" >/dev/null 2>&1 \
        && [[ -s "$target" ]]; then
        actual_sha256="$(file_sha256 "$target")"
        actual_bytes="$(file_size_bytes "$target")"
        if jq -e \
          --arg sha256 "$actual_sha256" \
          --argjson bytes "$actual_bytes" \
          '.actualPNG.sha256 == $sha256 and .actualPNG.bytes == $bytes' \
          "$CAPTURE_ACK_FILE" >/dev/null 2>&1; then
          return 0
        fi
        echo "application-owned capture acknowledgement hash/size mismatch: $target" >"$SCREENSHOT_ERROR"
        cat "$SCREENSHOT_ERROR" >&2 || true
        return 1
      fi
      jq -r '
        if .status != "succeeded" then
          .failureReason // "application-owned capture failed without a reason"
        else
          "application-owned capture acknowledgement did not prove stable required pane state"
        end
      ' "$CAPTURE_ACK_FILE" >"$SCREENSHOT_ERROR"
      cat "$SCREENSHOT_ERROR" >&2 || true
      return 1
    fi
    refresh_app_pid || true
    sleep 0.25
  done
  echo "application-owned capture timed out after 30 seconds: $target" >"$SCREENSHOT_ERROR"
  cat "$SCREENSHOT_ERROR" >&2 || true
  return 1
}

wait_for_action_receipt() {
  rm -f "$ACTION_RECEIPT_ARCHIVE"
  for _ in {1..80}; do
    if [[ -s "$ACTION_RECEIPT_WORKSPACE" ]] \
      && jq -e --arg caseID "$CASE_ID" --arg caseKind "$CASE_KIND" '
        .schemaVersion == 1
        and .stage == "after"
        and .changed == true
        and (.timestamp | type == "string" and length > 0)
        and (($caseID == "") or (.case.id == $caseID))
        and (($caseKind == "") or (.case.kind == $caseKind))
        and (.scene.id | type == "string" and length > 0)
        and (.scene.title | type == "string" and length > 0)
        and (.target | type == "object")
        and ([.target.id?, .target.control?, .target.label?] | map(select(type == "string" and length > 0)) | length > 0)
        and (.kind | type == "string" and length > 0)
        and has("before")
        and has("after")
        and (.before != .after)
      ' "$ACTION_RECEIPT_WORKSPACE" >/dev/null 2>&1; then
      cp "$ACTION_RECEIPT_WORKSPACE" "$ACTION_RECEIPT_ARCHIVE"
      return 0
    fi
    refresh_app_pid || true
    sleep 0.25
  done
  {
    echo "application-owned interaction receipt missing or unchanged"
    if [[ -s "$ACTION_RECEIPT_WORKSPACE" ]]; then
      echo "--- last receipt ---"
      cat "$ACTION_RECEIPT_WORKSPACE"
    fi
  } >"$ACTION_ERROR"
  cat "$ACTION_ERROR" >&2 || true
  return 1
}

capture_ax_snapshot() {
  local target="$1"
  local error_target="$2"
  rm -f "$target" "$error_target"
  if "$AX_BINARY" "$APP_PID" dump >"$target.tmp" 2>"$error_target"; then
    mv "$target.tmp" "$target"
  else
    rm -f "$target.tmp"
    : >"$target"
  fi
}

run_visual_gate() {
  local mode="$1"
  local gate_log="$OUTPUT_DIR/quality-gate.log"
  rm -f "$QUALITY_GATE_JSON"
  if [[ "$mode" == "single" ]]; then
    "$VISUAL_GATE_BINARY" \
      --single "$SINGLE_SCREENSHOT" \
      --single-ack "$SINGLE_CAPTURE_ACK" \
      --ax-before "$AX_BEFORE" \
      --output "$QUALITY_GATE_JSON" >"$gate_log"
  else
    "$VISUAL_GATE_BINARY" \
      --overview "$OVERVIEW_SCREENSHOT" \
      --before "$BEFORE_SCREENSHOT" \
      --after "$AFTER_SCREENSHOT" \
      --overview-ack "$OVERVIEW_CAPTURE_ACK" \
      --before-ack "$BEFORE_CAPTURE_ACK" \
      --after-ack "$AFTER_CAPTURE_ACK" \
      --ax-before "$AX_BEFORE" \
      --ax-after "$AX_AFTER" \
      --action-receipt "$ACTION_RECEIPT_ARCHIVE" \
      --case-id "$CASE_ID" \
      --case-kind "$CASE_KIND" \
      --output "$QUALITY_GATE_JSON" >"$gate_log"
  fi
}

finish_with_quality_gate() {
  local capture_kind="$1"
  local gate_status
  gate_status="$(jq -r '.status // "fail"' "$QUALITY_GATE_JSON" 2>/dev/null || printf 'fail')"
  if [[ "$gate_status" == "fail" ]]; then
    json_manifest "failed" "automatic technical layout quality gate failed" "$capture_kind"
    echo "rich-answer evidence captured, but automatic quality gate failed: $QUALITY_GATE_JSON" >&2
    exit 31
  fi
  json_manifest "succeeded" "" "$capture_kind"
  if [[ "$gate_status" == "warn" ]]; then
    echo "rich-answer evidence captured with automatic quality warnings: $QUALITY_GATE_JSON" >&2
  fi
}

should_capture_single=0
if [[ "$SINGLE_SHOT" == "1" ]]; then
  should_capture_single=1
elif [[ -s "$ERROR_FILE" ]]; then
  should_capture_single=1
elif [[ -n "$CASE_KIND" && "$CASE_KIND" != "rich" ]]; then
  should_capture_single=1
elif [[ -s "$MARKER_FILE" ]] && grep -qE 'richAnswer=none|scenes=0' "$MARKER_FILE"; then
  should_capture_single=1
fi

if [[ "$should_capture_single" == "1" ]]; then
  capture_window "$SINGLE_SCREENSHOT" 0 || fail_with_manifest 14 "rich-answer evidence smoke failed: could not capture single window screenshot" "single"
  "$AX_BINARY" "$APP_PID" dump >"$AX_BEFORE" || true
  run_visual_gate "single" || fail_with_manifest 17 "rich-answer evidence smoke failed: automatic visual gate could not run" "single"
  finish_with_quality_gate "single"
  echo "rich_answer_evidence_dir=$OUTPUT_DIR"
  echo "rich_answer_single=$SINGLE_SCREENSHOT"
  echo "rich_answer_manifest=$MANIFEST_JSON"
  exit 0
fi

renderer_seen=0
for _ in {1..120}; do
  if [[ -s "$RENDERER_READY_FILE" ]]; then
    renderer_seen=1
    break
  fi
  refresh_app_pid || true
  sleep 0.25
done
if [[ "$renderer_seen" != "1" ]]; then
  fail_with_manifest 16 "rich-answer evidence smoke failed: renderer-ready marker missing before rich capture" "rich-interaction"
fi

if ! "$AX_BINARY" "$APP_PID" ready >"$OUTPUT_DIR/ax-ready.txt" 2>"$OUTPUT_DIR/ax-ready.err"; then
  printf 'AX tree unavailable; continuing with application-owned verification stages.\n' >"$OUTPUT_DIR/ax-ready.txt"
fi

capture_window "$OVERVIEW_SCREENSHOT" 1 || fail_with_manifest 14 "rich-answer evidence smoke failed: could not capture overview window screenshot" "rich-interaction"
capture_window "$BEFORE_SCREENSHOT" 1 || fail_with_manifest 14 "rich-answer evidence smoke failed: could not capture before window screenshot" "rich-interaction"
capture_ax_snapshot "$AX_BEFORE" "$OUTPUT_DIR/ax-before.err"

if [[ "$MANUAL_REVIEW_HOLD_SECONDS" =~ ^[0-9]+$ ]] && (( MANUAL_REVIEW_HOLD_SECONDS > 0 )); then
  printf '%s\n' "$APP_PID" >"$OUTPUT_DIR/manual-review-hold-ready.txt"
  sleep "$MANUAL_REVIEW_HOLD_SECONDS"
fi

rm -f "$ACTION_RECEIPT_WORKSPACE" "$ACTION_RECEIPT_ARCHIVE"
capture_window "$AFTER_SCREENSHOT" 1 || fail_with_manifest 14 "rich-answer evidence smoke failed: could not capture after window screenshot" "rich-interaction"
capture_ax_snapshot "$AX_AFTER" "$OUTPUT_DIR/ax-after.err"
: >"$ACTION_ERROR"
wait_for_action_receipt || fail_with_manifest 30 "rich-answer evidence smoke failed: application interaction receipt missing or unchanged" "rich-interaction"
action_receipt_sha256="$(file_sha256 "$ACTION_RECEIPT_ARCHIVE")"
action_receipt_bytes="$(file_size_bytes "$ACTION_RECEIPT_ARCHIVE")"
after_sha256="$(file_sha256 "$AFTER_SCREENSHOT")"
after_bytes="$(file_size_bytes "$AFTER_SCREENSHOT")"
jq -n \
  --arg method "application-owned-interaction-receipt" \
  --arg caseID "$CASE_ID" \
  --arg caseKind "$CASE_KIND" \
  --arg afterPath "$AFTER_SCREENSHOT" \
  --arg afterSha256 "$after_sha256" \
  --arg afterBytes "$after_bytes" \
  --arg receiptPath "$ACTION_RECEIPT_ARCHIVE" \
  --arg receiptSha256 "$action_receipt_sha256" \
  --arg receiptBytes "$action_receipt_bytes" \
  --slurpfile request "$AFTER_CAPTURE_REQUEST" \
  --slurpfile acknowledgement "$AFTER_CAPTURE_ACK" \
  --slurpfile receipt "$ACTION_RECEIPT_ARCHIVE" \
  '{
    method: $method,
    stage: "after",
    succeeded: true,
    case: {
      id: (if $caseID == "" then null else $caseID end),
      kind: (if $caseKind == "" then null else $caseKind end)
    },
    afterScreenshot: {
      path: $afterPath,
      sha256: $afterSha256,
      bytes: ($afterBytes | tonumber)
    },
    receiptFile: {
      path: $receiptPath,
      sha256: $receiptSha256,
      bytes: ($receiptBytes | tonumber)
    },
    proof: {
      caseID: (if $caseID == "" then null else $caseID end),
      sceneID: $receipt[0].scene.id,
      changed: $receipt[0].changed,
      afterPNG: {
        sha256: $afterSha256,
        bytes: ($afterBytes | tonumber)
      },
      receipt: {
        sha256: $receiptSha256,
        bytes: ($receiptBytes | tonumber)
      }
    },
    receipt: $receipt[0],
    request: $request[0],
    acknowledgement: $acknowledgement[0]
  }' >"$ACTION_RESULT"

run_visual_gate "rich-interaction" || fail_with_manifest 17 "rich-answer evidence smoke failed: automatic visual gate could not run" "rich-interaction"
finish_with_quality_gate "rich-interaction"

cat >"$OUTPUT_DIR/manifest.txt" <<EOF
scenario=$SCENARIO
replay=$REPLAY_ARTIFACT
case_id=$CASE_ID
case_kind=$CASE_KIND
record=$RECORD_PATH
configuration=$CONFIGURATION
app_pid=$APP_PID
window_id=$WINDOW_ID
workspace=$WORKSPACE_DIR
overview=$OVERVIEW_SCREENSHOT
before=$BEFORE_SCREENSHOT
after=$AFTER_SCREENSHOT
ax_before=$AX_BEFORE
ax_after=$AX_AFTER
action=$ACTION_RESULT
action_receipt=$ACTION_RECEIPT_ARCHIVE
marker=$MARKER_FILE
stdout=$APP_STDOUT
stderr=$APP_STDERR
json_manifest=$MANIFEST_JSON
EOF

echo "rich_answer_evidence_dir=$OUTPUT_DIR"
echo "rich_answer_overview=$OVERVIEW_SCREENSHOT"
echo "rich_answer_before=$BEFORE_SCREENSHOT"
echo "rich_answer_after=$AFTER_SCREENSHOT"
echo "rich_answer_action=$ACTION_RESULT"
echo "rich_answer_manifest=$MANIFEST_JSON"
