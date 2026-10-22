#!/usr/bin/env bash
set -euo pipefail
# Real windows are permitted only on the isolated CI desktop.
[[ "${CI:-}" == true ]] || { echo '本机候选请在画中画验收。' >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SCENARIO=all
if (( $# > 0 )); then
  [[ $# == 2 && "$1" == --scenario ]] || { echo 'usage: check-ci.sh [--scenario all|conversation|business|picker]' >&2; exit 2; }
  SCENARIO="$2"
fi
case "$SCENARIO" in all|conversation|business|picker) ;; *) echo 'unknown diagnostic scenario' >&2; exit 2 ;; esac
export WEIBEI_ACCEPTANCE_SCENARIO="$SCENARIO"
python3 App/script/business-server.test.py
node --test App/script/floating-label-check.test.mjs App/script/mermaid-measurement-observer.test.mjs App/script/mermaid-mounted-label-geometry.test.mjs
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/weibei-business-ci.XXXXXX")"
python3 App/script/business-server.py --output "$CHECK_DIR" > "$CHECK_DIR/server.log" 2>&1 &
server_pid=$!
mkdir -p App/Evidence
save_evidence() {
  kill "$server_pid" 2>/dev/null || true
  for file in "$CHECK_DIR/server.log" "$CHECK_DIR/requests.jsonl" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/latest.json" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/window.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/selection-probe-failure.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Workspace/business-check.json" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Workspace/business-failure.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/selection-composers.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/selection-discussion.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/selection-discussion-mist.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/selection-capsule-main.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/selection-capsule-floating.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/connection-cards.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/confirmed-import.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/contextual-pickers.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/selection-rich-answer-11pt.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/floating-rich-diagnostic.json" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/reasoning-composer.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/"onboarding-*.png \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/toolbar-navigation.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/toolbar-panes.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/toolbar-actions.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Workspace/quit-save.json"; do
    [[ ! -f "$file" ]] || cp "$file" "App/Evidence/ci-$(basename "$file")"
  done
}
trap save_evidence EXIT
for _ in {1..600}; do
  [[ ! -s "$CHECK_DIR/endpoint.txt" ]] || break
  kill -0 "$server_pid"
  sleep 0.1
done
[[ -s "$CHECK_DIR/endpoint.txt" ]] || { cat "$CHECK_DIR/server.log" >&2; echo '测试服务未就绪' >&2; exit 1; }
WEIBEI_BUSINESS_CHECK_ENDPOINT="$(cat "$CHECK_DIR/endpoint.txt")"
export WEIBEI_BUSINESS_CHECK_ENDPOINT
export WEIBEI_BUNDLE_IDENTIFIER="com.changfenhuang.weibei.ci.$(uuidgen | tr '[:upper:]' '[:lower:]').businesscheck"
export WEIBEI_ACCEPTANCE_CHECKS=1
./script/build_and_run.sh package
export CHECK_APP="$ROOT/dist/acceptance/魏碑.app"
export CHECK_SUPPORT="$HOME/Library/Application Support/$WEIBEI_BUNDLE_IDENTIFIER"
export CHECK_SOURCE="$(git rev-parse HEAD)"
mkdir -p App/Evidence
python3 - <<'PY'
import json, os, shutil, subprocess, sys, tempfile, time
from pathlib import Path
app = os.environ['CHECK_APP']
support = Path(os.environ['CHECK_SUPPORT'])
source = os.environ['CHECK_SOURCE']
evidence = Path('App/Evidence')
scenario = os.environ['WEIBEI_ACCEPTANCE_SCENARIO']

def launch(argument):
    subprocess.run(['open', '-n', '-W', app, '--args', argument], check=True, timeout=360)

def verify(path, source_key, status=None):
    result = json.loads(path.read_text())
    assert result[source_key] == source and result['source_dirty'] is False, result
    assert result['platform'] == 'Mac Catalyst', result
    assert result['checks'] and all(v == 'passed' for v in result['checks'].values()), result
    assert status is None or result['status'] == status, result
    return result

conversation = None
if scenario in ('all', 'conversation'):
    launch('--self-check')
    conversation = verify(support / 'Results/latest.json', 'source_revision')
required_conversation_checks = {
    'empty_conversation_scroll_does_not_load_history', 'hover_strip_attachment_preserves_input',
    'prepend_preserves_reading_text', 'resize_preserves_reading_paragraph',
    'drag_reflows_visible_only_then_converges', 'closing_conversation_releases_width_worker',
    'stream_keeps_unchanged_blocks_and_tail', 'replay_stop_complete_and_history_reading',
    'image_arrival_preserves_reading_text', 'cross_paragraph_copy_survives_reuse',
    'selection_primary_press_reverse_and_capsule', 'card_draft_and_fold_persist',
    'code_highlight_selection_and_scroll_persist', 'math_image_and_diagram_resources',
    'single_long_answer_complete_and_revisitable',
}
if conversation:
    assert conversation['idiom'] == 'mac' and required_conversation_checks <= conversation['checks'].keys(), conversation
    for filename in ['latest.json', 'window.png', 'diagram.png']:
        shutil.copy2(support / 'Results' / filename, evidence / ('ci-conversation-' + filename))
if scenario == 'conversation':
    print('会话定向诊断通过；不替代完整合并检查。')
    sys.exit(0)

business_path = support / 'Workspace/business-check.json'
# Xcode's UI testing service drives real SwiftUI controls from another process.
# The App keeps the file, credential and recovery assertions in the same checks.
ui_log = evidence / 'ci-onboarding-ui.log'
with ui_log.open('w') as log:
    ui_result = subprocess.run([
        'xcodebuild', '-project', 'App/UITests/WeiBeiOnboardingUI.xcodeproj', '-scheme', 'WeiBeiOnboardingUITests',
        '-destination', 'platform=macOS,arch=' + os.environ['WEIBEI_TARGET_ARCH'],
        '-derivedDataPath', '.build/onboarding-ui-' + os.environ['WEIBEI_TARGET_ARCH'],
        '-resultBundlePath', str(evidence / 'ci-onboarding-ui.xcresult'),
        '-parallel-testing-enabled', 'NO',
        'WEIBEI_CHECK_APP_PATH=' + app, 'test',
    ], stdout=log, stderr=subprocess.STDOUT)
if ui_result.returncode:
    print(ui_log.read_text()[-16000:])
ui_result.check_returncode()
if scenario == 'picker':
    focused = verify(business_path, 'source', 'diagnostic_passed')
    assert focused['scenario'] == 'picker'
    assert focused['checks']['material_and_note_pickers_align'] == 'passed'
    shutil.copy2(business_path, evidence / 'ci-picker-diagnostic.json')
    print('选择界面定向诊断通过；不替代完整合并检查。')
    sys.exit(0)
verify(business_path, 'source', 'awaiting_reopen')
launch('--exit-after-check')
business = verify(business_path, 'source', 'passed')
required_business_checks = {
    'library_onboarding_failure_retry_picker_cancel_and_recovery',
    'chat_inline_connection_cancel_retry_models_and_draft',
    'native_citation_typography_and_hover_title',
    'active_connection_profile_matches_configuration', 'connection_profile_switch_back',
    'connection_cards_settings_and_authenticated_models',
    'settings_panel_stays_in_original_full_screen_window',
    'material_and_note_pickers_align',
    'confirmed_import_review_copy_and_dismiss',
    'workspace_file_drop_receiver',
    'workspace_external_transfer_preserves_bytes_and_cleans_staging',
    'reopen_original_note_and_session_files', 'mac_idiom_and_isolated_storage',
    'original_update_service_through_native_bridge', 'native_workspace_toolbar_controls',
    'update_popover_first_pointer_click',
    'native_toolbar_reader_pointer_toggle', 'native_toolbar_settings_pointer_open',
    'native_toolbar_agent_pointer_toggle', 'native_toolbar_notes_pointer_toggle',
    'native_toolbar_library_pointer_toggle',
    'native_toolbar_appearance_pointer_toggle',
    'native_toolbar_render_snapshots',
    'native_toolbar_full_screen_settings_pointer_open',
    'signed_native_window_material', 'original_import_reader_and_editor',
    'original_editor_snapshot_and_note_write_gate', 'signed_bounded_pdf_worker',
    'waiting_status_not_clipped', 'return_clears_original_composer',
    'status_disappears_at_first_text', 'original_http_agent_tools_and_uikit_stream',
    'original_source_navigation', 'original_attachment_loader',
    'image_mounted_in_visible_message', 'original_answer_to_note',
    'selection_chat_composers_and_citation', 'stop_preserves_received_text',
    'divider_batches_widths_and_reflows_during_drag',
    'conversation_appearance_and_scale_after_resize',
    'history_and_long_answer_through_original_messages',
    'floating_11pt_math_diagram_and_layout',
    'divider_interface_language_updates',
}
# Require all baseline, floating, language, import, and connection gates; verify() above
# rejects failures in additional gates as well.
assert required_business_checks <= business['checks'].keys(), business
assert business['floating_rich_answer']['body_font_size_pt'] == 11, business
assert business['floating_rich_answer']['math_images'] == 2, business
shutil.copy2(business_path, evidence / 'ci-business.json')
shutil.copy2(support / 'Results/workspace.png', evidence / 'ci-business-window.png')
for filename in ['onboarding-library-failure.png', 'onboarding-library-recovered.png', 'onboarding-chat-credentials.png', 'onboarding-chat-rejected.png', 'onboarding-chat-models.png', 'onboarding-chat-ready.png', 'selection-composers.png', 'selection-discussion.png', 'selection-capsule-main.png', 'selection-capsule-floating.png', 'connection-cards.png', 'confirmed-import.png', 'selection-rich-answer-11pt.png', 'reasoning-composer.png', 'toolbar-navigation.png', 'toolbar-panes.png', 'toolbar-actions.png']:
    shutil.copy2(support / 'Results' / filename, evidence / ('ci-' + filename))
print(f"{len(conversation['checks']) if conversation else 0} 项会话检查与 {len(business['checks'])} 项原业务保存重开检查通过；含选区胶囊、浮窗 11pt 公式与图示、原生工具栏、选区双输入框与引用定位，不替代鼠标、输入法及触控板体验验收。")
if scenario == 'business':
    print('业务定向诊断通过；不替代完整合并检查。')
    sys.exit(0)

with tempfile.TemporaryDirectory(prefix='weibei-quit-check-') as scratch:
    helper = str(Path(scratch) / 'quit')
    subprocess.run(['swiftc', '-o', helper, '-'], input='''
import AppKit
guard let pid = Int32(CommandLine.arguments[1]),
      let app = NSRunningApplication(processIdentifier: pid), app.terminate() else { exit(1) }
''', text=True, check=True)
    running = subprocess.Popen(['open', '-n', '-W', app, '--args', '--quit-save-check'])
    quit_path = support / 'Workspace/quit-save.json'
    deadline = time.monotonic() + 60
    while not quit_path.exists():
        assert running.poll() is None and time.monotonic() < deadline, '退出保存检查未到达写入阶段'
        time.sleep(0.05)
    pending = json.loads(quit_path.read_text())
    assert pending['status'] == 'awaiting_quit', pending
    subprocess.run([helper, str(pending['pid'])], check=True, timeout=10)
    assert running.wait(timeout=60) == 0, '正常退出失败'
    launch('--verify-quit-save')
    saved = json.loads(quit_path.read_text())
    assert saved['status'] == 'passed' and saved['source'] == source and saved['source_dirty'] is False, saved
    shutil.copy2(quit_path, evidence / 'ci-quit-save.json')
print('真实退出并重开后，笔记内容与动作执行状态一致。')
PY
