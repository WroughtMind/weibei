#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d -t weibei-ra-gate-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

BATCH_SCRIPT="$ROOT_DIR/script/rich-answer-evidence-batch.sh"
VISUAL_GATE_SOURCE="$ROOT_DIR/script/rich-answer-visual-gate.swift"
VISUAL_GATE_BIN="$TEST_DIR/rich-answer-visual-gate"
SMOKE_SOURCE="$ROOT_DIR/script/rich-answer-evidence-smoke.sh"

if rg -q 'as\? \[AXUIElement\]' "$SMOKE_SOURCE"; then
  echo "rich-answer evidence helper must decode AX element arrays through CFArray, not Swift bridging" >&2
  exit 1
fi
rg -q 'CFArrayGetValueAtIndex' "$SMOKE_SOURCE"
rg -q 'AXUIElementCopyAttributeValues' "$SMOKE_SOURCE"

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

file_bytes() {
  /usr/bin/wc -c <"$1"
}

build_visual_gate() {
  local sdk_root
  local cache_dir
  local swiftc_path="/usr/bin/swiftc"
  sdk_root="${SDKROOT:-$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || printf '%s' '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk')}"
  cache_dir="$TEST_DIR/clang-module-cache"
  mkdir -p "$cache_dir"
  SWIFT_MODULE_CACHE_PATH="$cache_dir" \
  SWIFTPM_MODULECACHE_OVERRIDE="$cache_dir" \
  CLANG_MODULE_CACHE_PATH="$cache_dir" \
    "$swiftc_path" -sdk "$sdk_root" -framework AppKit "$VISUAL_GATE_SOURCE" -o "$VISUAL_GATE_BIN"
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "ASSERTION FAILED: $message (actual=$actual expected=$expected)" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "ASSERTION FAILED: $message (missing: $needle)" >&2
    echo "content: $haystack" >&2
    exit 1
  fi
}

write_rich_answer_ack() {
  local stage="$1"
  local image_path="$2"
  local output_path="$3"
  local sha
  local bytes
  sha="$(sha256_file "$image_path")"
  bytes="$(file_bytes "$image_path")"

  cat >"$output_path" <<EOF
{
  "status": "succeeded",
  "stage": "$stage",
  "requestCapturePath": "$image_path",
  "capturePath": "$image_path",
  "actualPNG": {
    "path": "$image_path",
    "sha256": "$sha",
    "bytes": $bytes
  },
  "captureWorkspaceState": {
    "stable": true,
    "start": {
      "showReader": true,
      "showAgent": true,
      "visiblePanes": ["reader", "agent"],
      "paneFrames": {
        "reader": {"x": 0, "y": 0, "width": 640, "height": 720},
        "agent": {"x": 640, "y": 0, "width": 640, "height": 720}
      }
    },
    "end": {
      "showReader": true,
      "showAgent": true,
      "visiblePanes": ["reader", "agent"],
      "paneFrames": {
        "reader": {"x": 0, "y": 0, "width": 640, "height": 720},
        "agent": {"x": 640, "y": 0, "width": 640, "height": 720}
      }
    }
  }
}
EOF
}

write_action_receipt() {
  local output_path="$1"
  local case_id="$2"
  local case_kind="$3"
  local changed="$4"
  local before_value="$5"
  local after_value="$6"

  cat >"$output_path" <<EOF
{
  "schemaVersion": 1,
  "stage": "after",
  "source": "web-runtime",
  "kind": "parameter-slider",
  "scene": {
    "id": "test-scene",
    "title": "测试场景"
  },
  "case": {
    "id": "$case_id",
    "kind": "$case_kind"
  },
  "changed": $changed,
  "before": {
    "target": {
      "value": "$before_value"
    }
  },
  "after": {
    "target": {
      "value": "$after_value"
    }
  }
}
EOF
}

write_ax_records_for_single() {
  local output_path="$1"
  cat >"$output_path" <<'EOF'
AXWindow role=AXWindow id=window title=window desc=desc value= frame=0,0,1280,720
AXGroup role=AXWindow id=stable-document-slot-reader title=reader desc= value=reader frame=0,0,640,720
AXGroup role=AXWindow id=stable-document-slot-agent title=agent desc= value=agent frame=640,0,640,720
AXButton role=AXButton id=doc.text title=隐藏文稿 desc=隐藏文稿 value= frame=30,30,28,28
AXButton role=AXButton id=bubble.left.and.text.bubble.right title=隐藏对话 desc=隐藏对话 value= frame=30,70,28,28
AXWebArea role=AXWebArea id=agent-answer title= desc=魏碑笔记 value= frame=680,90,600,310
AXTextField role=AXTextField id=plain-text-body title=正文 desc= value=这是一次可以复核的多行 Pi 回答，
第二行仍然必须被 AX 解析器识别为真实正文 frame=700,110,560,80
AXStaticText role=AXText id=plain-text-summary title=总结 desc= value=该示例用于验证单张证据可视化门控是否通过 frame=700,210,560,80
AXList role=AXList id=plain-answer-list title=列表 desc= value=这是列表记录第一项，文字完整且有语义 frame=700,310,560,72
EOF
}

write_ax_records_for_rich() {
  local output_path="$1"
  cat >"$output_path" <<'EOF'
AXWindow role=AXWindow id=window title=window desc=desc value= frame=0,0,1280,720
AXGroup role=AXWindow id=stable-document-slot-reader title=reader desc= value=reader frame=0,0,640,720
AXGroup role=AXWindow id=stable-document-slot-agent title=agent desc= value=agent frame=640,0,640,720
AXButton role=AXButton id=doc.text title=隐藏文稿 desc=隐藏文稿 value= frame=30,30,28,28
AXButton role=AXButton id=bubble.left.and.text.bubble.right title=隐藏对话 desc=隐藏对话 value= frame=30,70,28,28
AXStaticText role=AXStaticText id=rich-answer-text title=富回答正文 desc= value=这是一次可以复核的富回答文本内容，长度足够并有真实语义 frame=700,110,560,80
AXStaticText role=AXStaticText id=rich-answer-summary title=富回答总结 desc= value=该示例用于验证富回答检验是否通过 frame=700,210,560,80
EOF
}

write_ax_records_for_rich_missing_reader() {
  local output_path="$1"
  cat >"$output_path" <<'EOF'
AXWindow role=AXWindow id=window title=window desc=desc value= frame=0,0,1280,720
AXGroup role=AXWindow id=stable-document-slot-agent title=agent desc= value=agent frame=640,0,640,720
AXButton role=AXButton id=bubble.left.and.text.bubble.right title=隐藏对话 desc=隐藏对话 value= frame=30,70,28,28
EOF
}

write_shifted_ax_records_for_rich() {
  local output_path="$1"
  local slider_value="$2"
  cat >"$output_path" <<EOF
AXWindow role=AXWindow id=window title=window desc=desc value= frame=100,40,1280,720
AXGroup role=AXGroup id=stable-document-slot-reader title=reader desc= value=reader frame=100,40,624,720
AXGroup role=AXGroup id=stable-document-slot-agent title=agent desc= value=agent frame=734,40,605,720
AXButton role=AXButton id=doc.text title=隐藏文稿 desc=隐藏文稿 value= frame=680,50,28,28
AXButton role=AXButton id=bubble.left.and.text.bubble.right title=隐藏对话 desc=隐藏对话 value= frame=720,50,28,28
AXGroup role=AXGroup id=rich-answer-scene-shifted title=富回答 desc= value= frame=780,90,542,620
AXSlider role=AXSlider id=rich-answer-control-shifted title=时间位置 desc=时间位置 value=$slider_value frame=780,360,541,16
EOF
}

write_ax_records_for_single_overflow() {
  local output_path="$1"
  cat >"$output_path" <<'EOF_AX'
AXWindow role=AXWindow id=window title=window desc=desc value= frame=0,0,1536,1024
AXGroup role=AXWindow id=stable-document-slot-reader title=reader desc= value=reader frame=0,0,700,1024
AXGroup role=AXWindow id=stable-document-slot-agent title=agent desc= value=agent frame=700,0,836,1024
AXButton role=AXButton id=doc.text title=隐藏文稿 desc=隐藏文稿 value= frame=30,30,28,28
AXButton role=AXButton id=bubble.left.and.text.bubble.right title=隐藏对话 desc=隐藏对话 value= frame=30,70,28,28
AXWebArea role=AXWebArea id=agent-answer title= desc=魏碑笔记 value= frame=700,50,836,370
AXStaticText role=AXStaticText id=single-safe-body title=正文 desc= value=这是一个完整落在窗格内可作为参考的正文内容 frame=700,60,560,80
AXStaticText role=AXStaticText id=single-overflow-body title=正文 desc= value=该内容明显超出 Agent 窗格宽度，测试越界失败场景 frame=700,110,920,80
AXText role=AXText id=single-overflow-summary title=总结 desc= value=右侧边界也会继续往外延展并触发 hard fail frame=700,310,920,80
EOF_AX
}

write_ax_records_for_single_placeholder() {
  local output_path="$1"
  cat >"$output_path" <<'EOF'
AXWindow role=AXWindow id=window title=window desc=desc value= frame=0,0,1536,1024
AXGroup role=AXWindow id=stable-document-slot-reader title=reader desc= value=reader frame=0,0,700,1024
AXGroup role=AXWindow id=stable-document-slot-agent title=agent desc= value=agent frame=700,0,836,1024
AXButton role=AXButton id=doc.text title=隐藏文稿 desc=隐藏文稿 value= frame=30,30,28,28
AXButton role=AXButton id=bubble.left.and.text.bubble.right title=隐藏对话 desc=隐藏对话 value= frame=30,70,28,28
AXStaticText role=AXStaticText id=user-question title=用户问题 desc= value=这是一段很长但不能冒充 Agent 回答的用户提问 frame=700,100,500,50
AXWebArea role=AXWebArea id=agent-answer title= desc=魏碑笔记 value= frame=700,180,500,80
AXStaticText role=AXStaticText id=single-placeholder-body title=正文 desc= value=结论 frame=700,200,220,30
EOF
}

write_ax_records_for_single_with_prompt_noise() {
  local output_path="$1"
  cat >"$output_path" <<'EOF'
AXWindow role=AXWindow id=window title=window desc=desc value= frame=0,0,1536,1024
AXGroup role=AXWindow id=stable-document-slot-reader title=reader desc= value=reader frame=0,0,700,1024
AXGroup role=AXWindow id=stable-document-slot-agent title=agent desc= value=agent frame=700,0,836,1024
AXText role=AXText id=chat-input title=输入框 desc=输入框 value=请输入问题 frame=700,70,220,28
AXStaticText role=AXStaticText id=bubble-history title=历史记录 desc=历史记录 value=上一个提问: 这是什么？ frame=700,120,500,24
AXStaticText role=AXStaticText id=single-noise-body title=正文 desc= value=这是输入提示语而非答案的占位说明 frame=700,170,500,30
AXWebArea role=AXWebArea id=agent-answer title= desc=魏碑笔记 value= frame=700,200,760,190
AXStaticText role=AXStaticText id=single-valid-answer title=正文 desc= value=这是一次可读的正文，说明场景已成功落在可见窗格内 frame=700,210,560,80
AXList role=AXList id=plain-answer-list title=列表 desc= value=列表记录第二项，长度和语义都充足 frame=700,310,560,72
AXButton role=AXButton id=bubble.left.and.text.bubble.right title=隐藏对话 desc=隐藏对话 value= frame=30,70,28,28
EOF
}

write_ax_records_for_single_list_answer() {
  local output_path="$1"
  cat >"$output_path" <<'EOF'
AXWindow role=AXWindow id=window title=window desc=desc value= frame=0,0,1536,1024
AXGroup role=AXWindow id=stable-document-slot-reader title=reader desc= value=reader frame=0,0,700,1024
AXGroup role=AXWindow id=stable-document-slot-agent title=agent desc= value=agent frame=700,0,836,1024
AXWebArea role=AXWebArea id=agent-answer title= desc=魏碑笔记 value= frame=700,100,760,160
AXStaticText role=AXStaticText id=chat-title title=标题 desc=标题 value=富回答标题 frame=700,80,220,28
AXList role=AXList id=plain-answer-list title=答案列表 desc= desc value=该列表记录用于验证列表回答 frame=700,120,760,28
AXListItem role=AXListItem id=plain-answer-list-item-1 title=列表项 desc= 第一条记录 value=第一条：列表形式的回答正文应当被识别为有效内容 frame=700,160,500,28
AXListItem role=AXListItem id=plain-answer-list-item-2 title=列表项 desc= 第二条记录 value=第二条：同样保持完整语义 frame=700,190,500,28
AXButton role=AXButton id=bubble.left.and.text.bubble.right title=隐藏对话 desc=隐藏对话 value= frame=30,70,28,28
EOF
}

write_ax_records_for_single_history_only() {
  local output_path="$1"
  cat >"$output_path" <<'EOF'
AXWindow role=AXWindow id=window title=window desc=desc value= frame=0,0,1536,1024
AXGroup role=AXWindow id=stable-document-slot-reader title=reader desc= value=reader frame=0,0,700,1024
AXGroup role=AXWindow id=stable-document-slot-agent title=agent desc= value=agent frame=700,0,836,1024
AXText role=AXText id=chat-input title=输入框 desc=输入框 value=请输入问题 frame=700,70,220,28
AXStaticText role=AXStaticText id=bubble-history title=历史记录 desc=历史记录 value=上一个提问：这是什么？ frame=700,110,500,24
AXStaticText role=AXStaticText id=prompt-hint title=输入提示 desc=输入提示 value=尝试输入更具体的问题 frame=700,140,500,24
AXButton role=AXButton id=bubble.left.and.text.bubble.right title=隐藏对话 desc=隐藏对话 value= frame=30,70,28,28
EOF
}

build_visual_gate

test_single_mode_with_readable_ax_is_accepted() {
  local out_dir="$TEST_DIR/single-pass"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local single_png="$out_dir/single.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax.txt"
  write_ax_records_for_single "$ax_before"
  cp "$source_png" "$single_png"

  "$VISUAL_GATE_BIN" \
    --single "$single_png" \
    --ax-before "$ax_before" \
    --output "$output_json"

  local status
  status="$(/usr/bin/jq -r '.status' "$output_json")"
  local interaction
  interaction="$(/usr/bin/jq -r '.checks[] | select(.id == "interaction-changed").status' "$output_json")"
  local width
  width="$(/usr/bin/jq -r '.checks[] | select(.id == "pane-width-stability").status' "$output_json")"
  local overflow
  overflow="$(/usr/bin/jq -r '.checks[] | select(.id == "content-overflow").status' "$output_json")"

  assert_eq "$status" "pass" "single evidence overall status should pass"
  assert_eq "$interaction" "pass" "single evidence interaction-changed should pass"
  assert_eq "$width" "pass" "single evidence pane-width-stability should pass"
  assert_eq "$overflow" "pass" "single evidence content-overflow should be checked"
  echo "PASS: single evidence mode treated as pass for interaction and pane width checks"
}

test_single_mode_without_rich_answer_identifier_is_accepted() {
  local out_dir="$TEST_DIR/single-pass-no-prefixed-id"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local single_png="$out_dir/single.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax.txt"
  write_ax_records_for_single_with_prompt_noise "$ax_before"
  cp "$source_png" "$single_png"

  "$VISUAL_GATE_BIN" \
    --single "$single_png" \
    --ax-before "$ax_before" \
    --output "$output_json"

  local status
  status="$(/usr/bin/jq -r '.status' "$output_json")"
  local overflow
  overflow="$(/usr/bin/jq -r '.checks[] | select(.id == "content-overflow").status' "$output_json")"

  assert_eq "$status" "pass" "single evidence without rich-answer-* should still pass"
  assert_eq "$overflow" "pass" "single evidence text overflow check should handle non-prefixed readable text"
  echo "PASS: single evidence can pass with non-prefixed readable answer text"
}

test_single_mode_list_item_answer_is_accepted() {
  local out_dir="$TEST_DIR/single-pass-list-item"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local single_png="$out_dir/single.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax.txt"
  write_ax_records_for_single_list_answer "$ax_before"
  cp "$source_png" "$single_png"

  "$VISUAL_GATE_BIN" \
    --single "$single_png" \
    --ax-before "$ax_before" \
    --output "$output_json"

  local status
  status="$(/usr/bin/jq -r '.status' "$output_json")"
  local overflow
  overflow="$(/usr/bin/jq -r '.checks[] | select(.id == "content-overflow").status' "$output_json")"

  assert_eq "$status" "pass" "single evidence with AXListItem answers should pass"
  assert_eq "$overflow" "pass" "single evidence list answers should pass overflow check"
  echo "PASS: single evidence accepts list/AXListItem answer records"
}

test_single_mode_history_only_should_fail() {
  local out_dir="$TEST_DIR/single-history-only"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local single_png="$out_dir/single.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax.txt"
  write_ax_records_for_single_history_only "$ax_before"
  cp "$source_png" "$single_png"

  "$VISUAL_GATE_BIN" \
    --single "$single_png" \
    --ax-before "$ax_before" \
    --output "$output_json"

  local status
  status="$(/usr/bin/jq -r '.status' "$output_json")"
  local overflow
  overflow="$(/usr/bin/jq -r '.checks[] | select(.id == "content-overflow").status' "$output_json")"

  assert_eq "$status" "fail" "single evidence with only history/input prompt should fail"
  assert_eq "$overflow" "fail" "single-only-history case should fail content-overflow validation"
  echo "PASS: single evidence rejects prompt/history-only AX"
}

test_single_mode_checks_content_overflow() {
  local out_dir="$TEST_DIR/single-overflow"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local single_png="$out_dir/single.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax.txt"

  cp "$source_png" "$single_png"
  write_ax_records_for_single_overflow "$ax_before"

  "$VISUAL_GATE_BIN" \
    --single "$single_png" \
    --ax-before "$ax_before" \
    --require-agent-pane true \
    --output "$output_json"

  local status
  status="$(/usr/bin/jq -r '.status' "$output_json")"
  local overflow
  overflow="$(/usr/bin/jq -r '.checks[] | select(.id == "content-overflow").status' "$output_json")"
  local required_pane
  required_pane="$(/usr/bin/jq -r '.checks[] | select(.id == "required-pane-visibility").status' "$output_json")"

  assert_eq "$status" "fail" "single evidence with rich text overflow should fail"
  assert_eq "$overflow" "fail" "single mode content-overflow should enforce text overflow checks"
  assert_eq "$required_pane" "pass" "single evidence with required agent pane should keep pane visibility"
  echo "PASS: single mode content-overflow is still enforced"
}

test_single_mode_empty_ax_should_fail() {
  local out_dir="$TEST_DIR/single-empty-ax"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local single_png="$out_dir/single.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax.txt"

  cp "$source_png" "$single_png"
  : >"$ax_before"

  "$VISUAL_GATE_BIN" \
    --single "$single_png" \
    --ax-before "$ax_before" \
    --output "$output_json"

  local status
  status="$(/usr/bin/jq -r '.status' "$output_json")"
  local overflow
  overflow="$(/usr/bin/jq -r '.checks[] | select(.id == "content-overflow").status' "$output_json")"

  assert_eq "$status" "fail" "single evidence with empty AX should fail"
  assert_eq "$overflow" "fail" "single evidence empty AX should fail content-overflow validation"
  echo "PASS: single mode empty AX fails content validation"
}

test_single_mode_placeholder_ax_should_fail() {
  local out_dir="$TEST_DIR/single-placeholder-ax"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local single_png="$out_dir/single.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax.txt"

  cp "$source_png" "$single_png"
  write_ax_records_for_single_placeholder "$ax_before"

  "$VISUAL_GATE_BIN" \
    --single "$single_png" \
    --ax-before "$ax_before" \
    --output "$output_json"

  local status
  status="$(/usr/bin/jq -r '.status' "$output_json")"
  local overflow
  overflow="$(/usr/bin/jq -r '.checks[] | select(.id == "content-overflow").status' "$output_json")"

  assert_eq "$status" "fail" "single evidence with placeholder text should fail"
  assert_eq "$overflow" "fail" "single placeholder AX should fail content-overflow validation"
  echo "PASS: single mode placeholder AX fails content validation"
}

test_rich_mode_no_interaction_fails() {
  local out_dir="$TEST_DIR/rich-no-interaction"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local before_png="$out_dir/before.png"
  local after_png="$out_dir/after.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax-before.txt"
  local ax_after="$out_dir/ax-after.txt"
  local before_ack="$out_dir/before.ack.json"
  local after_ack="$out_dir/after.ack.json"

  cp "$source_png" "$before_png"
  cp "$source_png" "$after_png"
  write_ax_records_for_single "$ax_before"
  write_ax_records_for_rich "$ax_after"
  write_rich_answer_ack before "$before_png" "$before_ack"
  write_rich_answer_ack after "$after_png" "$after_ack"

  "$VISUAL_GATE_BIN" \
    --before "$before_png" \
    --after "$after_png" \
    --before-ack "$before_ack" \
    --after-ack "$after_ack" \
    --ax-before "$ax_before" \
    --ax-after "$ax_after" \
    --output "$output_json"

  local status
  status="$(/usr/bin/jq -r '.status' "$output_json")"
  local interaction
  interaction="$(/usr/bin/jq -r '.checks[] | select(.id == "interaction-changed").status' "$output_json")"

  assert_eq "$status" "fail" "rich evidence with no interaction change should fail"
  assert_eq "$interaction" "fail" "interaction-changed should fail when no visual/control delta"
  echo "PASS: rich interaction-nonchange is hard fail"
}

test_rich_mode_accepts_verified_action_receipt() {
  local out_dir="$TEST_DIR/rich-valid-action-receipt"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local before_png="$out_dir/before.png"
  local after_png="$out_dir/after.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax-before.txt"
  local ax_after="$out_dir/ax-after.txt"
  local action_receipt="$out_dir/action-receipt.json"
  local case_id="test-rich-action-receipt"

  cp "$source_png" "$before_png"
  cp "$source_png" "$after_png"
  write_ax_records_for_rich "$ax_before"
  write_ax_records_for_rich "$ax_after"
  write_action_receipt "$action_receipt" "$case_id" rich true 6 9

  "$VISUAL_GATE_BIN" \
    --before "$before_png" \
    --after "$after_png" \
    --ax-before "$ax_before" \
    --ax-after "$ax_after" \
    --action-receipt "$action_receipt" \
    --case-id "$case_id" \
    --case-kind rich \
    --output "$output_json"

  assert_eq "$(/usr/bin/jq -r '.status' "$output_json")" "pass" "valid application action receipt should prove interaction without relaxing image thresholds"
  assert_eq "$(/usr/bin/jq -r '.checks[] | select(.id == "interaction-changed").status' "$output_json")" "pass" "interaction should pass with a matching changed receipt"
  assert_eq "$(/usr/bin/jq -r '.checks[] | select(.id == "interaction-changed").metrics.applicationReceiptChanged' "$output_json")" "true" "interaction metrics should expose receipt evidence"
  echo "PASS: matching application action receipt proves a real interaction change"
}

test_rich_mode_rejects_mismatched_action_receipt() {
  local out_dir="$TEST_DIR/rich-mismatched-action-receipt"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local before_png="$out_dir/before.png"
  local after_png="$out_dir/after.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax-before.txt"
  local ax_after="$out_dir/ax-after.txt"
  local action_receipt="$out_dir/action-receipt.json"

  cp "$source_png" "$before_png"
  cp "$source_png" "$after_png"
  write_ax_records_for_rich "$ax_before"
  write_ax_records_for_rich "$ax_after"
  write_action_receipt "$action_receipt" wrong-case rich true 6 9

  if "$VISUAL_GATE_BIN" \
    --before "$before_png" \
    --after "$after_png" \
    --ax-before "$ax_before" \
    --ax-after "$ax_after" \
    --action-receipt "$action_receipt" \
    --case-id expected-case \
    --case-kind rich \
    --output "$output_json"; then
    echo "ASSERTION FAILED: mismatched action receipt should return a non-zero status" >&2
    exit 1
  fi

  assert_eq "$(/usr/bin/jq -r '.status' "$output_json")" "fail" "mismatched action receipt must fail"
  assert_contains "$(/usr/bin/jq -r '.checks[] | select(.id == "visual-gate-runtime").summary' "$output_json")" "case id does not match" "mismatched receipt failure should remain explicit"
  echo "PASS: action receipt cannot be reused across cases"
}

test_rich_mode_rejects_unchanged_action_receipt() {
  local out_dir="$TEST_DIR/rich-unchanged-action-receipt"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local before_png="$out_dir/before.png"
  local after_png="$out_dir/after.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax-before.txt"
  local ax_after="$out_dir/ax-after.txt"
  local action_receipt="$out_dir/action-receipt.json"

  cp "$source_png" "$before_png"
  cp "$source_png" "$after_png"
  write_ax_records_for_rich "$ax_before"
  write_ax_records_for_rich "$ax_after"
  write_action_receipt "$action_receipt" unchanged-case rich false 6 6

  if "$VISUAL_GATE_BIN" \
    --before "$before_png" \
    --after "$after_png" \
    --ax-before "$ax_before" \
    --ax-after "$ax_after" \
    --action-receipt "$action_receipt" \
    --case-id unchanged-case \
    --case-kind rich \
    --output "$output_json"; then
    echo "ASSERTION FAILED: unchanged action receipt should return a non-zero status" >&2
    exit 1
  fi

  assert_eq "$(/usr/bin/jq -r '.status' "$output_json")" "fail" "unchanged action receipt must fail"
  assert_contains "$(/usr/bin/jq -r '.checks[] | select(.id == "visual-gate-runtime").summary' "$output_json")" "invalid or unchanged" "unchanged receipt failure should remain explicit"
  echo "PASS: unchanged action receipt cannot fake interaction evidence"
}

test_rich_mode_missing_required_pane_is_hard_fail() {
  local out_dir="$TEST_DIR/rich-missing-required-pane"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local before_png="$out_dir/before.png"
  local after_png="$out_dir/after.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax-before.txt"
  local ax_after="$out_dir/ax-after.txt"
  local before_ack="$out_dir/before.ack.json"
  local after_ack="$out_dir/after.ack.json"

  cp "$source_png" "$before_png"
  cp "$source_png" "$after_png"
  write_ax_records_for_rich_missing_reader "$ax_before"
  write_ax_records_for_rich_missing_reader "$ax_after"
  write_rich_answer_ack before "$before_png" "$before_ack"
  write_rich_answer_ack after "$after_png" "$after_ack"

  "$VISUAL_GATE_BIN" \
    --before "$before_png" \
    --after "$after_png" \
    --before-ack "$before_ack" \
    --after-ack "$after_ack" \
    --ax-before "$ax_before" \
    --ax-after "$ax_after" \
    --require-reader-pane true \
    --require-agent-pane true \
    --output "$output_json"

  local status
  status="$(/usr/bin/jq -r '.status' "$output_json")"
  local required_pane
  required_pane="$(/usr/bin/jq -r '.checks[] | select(.id == "required-pane-visibility").status' "$output_json")"

  assert_eq "$status" "fail" "rich evidence missing required pane should fail"
  assert_eq "$required_pane" "fail" "required-pane-visibility should hard-fail when pane evidence missing"
  echo "PASS: missing required panes still hard fail"
}

test_rich_mode_prefers_global_ax_panes_over_local_ack_frames() {
  local out_dir="$TEST_DIR/rich-global-ax-local-ack"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local before_png="$out_dir/before.png"
  local after_png="$out_dir/after.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax-before.txt"
  local ax_after="$out_dir/ax-after.txt"
  local before_ack="$out_dir/before.ack.json"
  local after_ack="$out_dir/after.ack.json"

  cp "$source_png" "$before_png"
  /usr/bin/sips --resampleWidth 1500 "$source_png" --out "$out_dir/after-resized.png" >/dev/null
  /usr/bin/sips --padToHeightWidth 1024 1536 --padColor FFFFFF "$out_dir/after-resized.png" --out "$after_png" >/dev/null
  write_shifted_ax_records_for_rich "$ax_before" 1
  write_shifted_ax_records_for_rich "$ax_after" 2
  write_rich_answer_ack before "$before_png" "$before_ack"
  write_rich_answer_ack after "$after_png" "$after_ack"

  "$VISUAL_GATE_BIN" \
    --before "$before_png" \
    --after "$after_png" \
    --before-ack "$before_ack" \
    --after-ack "$after_ack" \
    --ax-before "$ax_before" \
    --ax-after "$ax_after" \
    --output "$output_json"

  assert_eq "$(/usr/bin/jq -r '.status' "$output_json")" "pass" "global AX panes should not be replaced by local acknowledgement frames"
  assert_eq "$(/usr/bin/jq -r '.checks[] | select(.id == "content-overflow").metrics.paneFrameSource' "$output_json")" "accessibility" "content overflow must compare frames in the same coordinate space"
  echo "PASS: global AX pane frames win over local app acknowledgement coordinates"
}

test_rich_mode_accepts_verified_ack_when_ax_tree_is_empty() {
  local out_dir="$TEST_DIR/rich-empty-ax-verified-ack"
  mkdir -p "$out_dir"
  local source_png="$ROOT_DIR/Docs/VisualReferences/富回答视觉探索-总览-01.png"
  local before_png="$out_dir/before.png"
  local after_png="$out_dir/after.png"
  local output_json="$out_dir/quality.json"
  local ax_before="$out_dir/ax-before.txt"
  local ax_after="$out_dir/ax-after.txt"
  local before_ack="$out_dir/before.ack.json"
  local after_ack="$out_dir/after.ack.json"

  cp "$source_png" "$before_png"
  /usr/bin/sips --resampleWidth 1500 "$source_png" --out "$out_dir/after-resized.png" >/dev/null
  /usr/bin/sips --padToHeightWidth 1024 1536 --padColor FFFFFF "$out_dir/after-resized.png" --out "$after_png" >/dev/null
  : >"$ax_before"
  : >"$ax_after"
  write_rich_answer_ack before "$before_png" "$before_ack"
  write_rich_answer_ack after "$after_png" "$after_ack"

  "$VISUAL_GATE_BIN" \
    --before "$before_png" \
    --after "$after_png" \
    --before-ack "$before_ack" \
    --after-ack "$after_ack" \
    --ax-before "$ax_before" \
    --ax-after "$ax_after" \
    --require-reader-pane true \
    --require-agent-pane true \
    --output "$output_json"

  assert_eq "$(/usr/bin/jq -r '.status' "$output_json")" "warn" "verified app acknowledgements should avoid a false failure while preserving unrelated visual warnings"
  assert_eq "$(/usr/bin/jq -r '.checks[] | select(.id == "source-grounded-rich-interaction-evidence").status' "$output_json")" "pass" "source-grounded evidence should accept hash-bound app acknowledgements"
  assert_eq "$(/usr/bin/jq -r '.checks[] | select(.id == "source-grounded-rich-interaction-evidence").metrics.stages[0].paneEvidenceSource' "$output_json")" "application-ack" "fallback source must remain explicit"
  echo "PASS: rich evidence accepts verified application acknowledgements when AX is unavailable"
}

test_batch_non_fixture_rejects_jobs_two() {
  local out_dir="$TEST_DIR/batch-jobs"
  mkdir -p "$out_dir"
  local index_path="$ROOT_DIR/Prototypes/RichAnswerEvidenceViewer/fixtures/demo-run/index.json"
  local log
  if log="$($BATCH_SCRIPT --index "$index_path" --jobs 2 --output-dir "$out_dir" 2>&1)"; then
    echo "ASSERTION FAILED: expected batch to reject --jobs 2 in non-fixture mode" >&2
    exit 1
  fi
  assert_contains "$log" "non-fixture" "batch should report non-fixture concurrency rejection"
  echo "PASS: batch rejects --jobs 2 outside fixture mode"
}

test_single_mode_with_readable_ax_is_accepted
test_single_mode_checks_content_overflow
test_single_mode_empty_ax_should_fail
test_single_mode_placeholder_ax_should_fail
test_single_mode_list_item_answer_is_accepted
test_single_mode_history_only_should_fail
test_single_mode_without_rich_answer_identifier_is_accepted
test_rich_mode_no_interaction_fails
test_rich_mode_accepts_verified_action_receipt
test_rich_mode_rejects_mismatched_action_receipt
test_rich_mode_rejects_unchanged_action_receipt
test_rich_mode_missing_required_pane_is_hard_fail
test_rich_mode_prefers_global_ax_panes_over_local_ack_frames
test_rich_mode_accepts_verified_ack_when_ax_tree_is_empty
test_batch_non_fixture_rejects_jobs_two

echo "All rich-answer pipeline tests passed."
