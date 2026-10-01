#!/usr/bin/env bash
set -euo pipefail
# Real windows are permitted only on the isolated CI desktop.
[[ "${CI:-}" == true ]] || { echo '本机候选请在画中画验收。' >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/weibei-business-ci.XXXXXX")"
python3 App/script/business-server.py --output "$CHECK_DIR" > "$CHECK_DIR/server.log" 2>&1 &
server_pid=$!
mkdir -p App/Evidence
save_evidence() {
  kill "$server_pid" 2>/dev/null || true
  for file in "$CHECK_DIR/server.log" "$CHECK_DIR/requests.jsonl" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Workspace/business-check.json" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Workspace/business-failure.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/selection-composers.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/selection-discussion.png" \
    "${CHECK_SUPPORT:-$CHECK_DIR}/Results/reasoning-composer.png" \
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
import json, os, shutil, subprocess, tempfile, time
from pathlib import Path
app = os.environ['CHECK_APP']
support = Path(os.environ['CHECK_SUPPORT'])
source = os.environ['CHECK_SOURCE']
evidence = Path('App/Evidence')

def launch(argument):
    subprocess.run(['open', '-n', '-W', app, '--args', argument], check=True, timeout=360)

def verify(path, source_key, status=None):
    result = json.loads(path.read_text())
    assert result[source_key] == source and result['source_dirty'] is False, result
    assert result['platform'] == 'Mac Catalyst', result
    assert result['checks'] and all(v == 'passed' for v in result['checks'].values()), result
    assert status is None or result['status'] == status, result
    return result

launch('--self-check')
conversation = verify(support / 'Results/latest.json', 'source_revision')
assert conversation['idiom'] == 'mac' and len(conversation['checks']) == 14, conversation
for filename in ['latest.json', 'window.png', 'diagram.png']:
    shutil.copy2(support / 'Results' / filename, evidence / ('ci-conversation-' + filename))

business_path = support / 'Workspace/business-check.json'
launch('--exit-after-check')
verify(business_path, 'source', 'awaiting_reopen')
launch('--exit-after-check')
business = verify(business_path, 'source', 'passed')
expected_business_checks = {
    'conversation_appearance_and_scale_after_resize',
    'divider_batches_widths_and_reflows_during_drag',
    'divider_interface_language_updates',
    'history_and_long_answer_through_original_messages',
    'image_mounted_in_visible_message',
    'mac_idiom_and_isolated_storage',
    'native_workspace_toolbar_controls',
    'original_answer_to_note',
    'original_attachment_loader',
    'original_editor_snapshot_and_note_write_gate',
    'original_http_agent_tools_and_uikit_stream',
    'original_import_reader_and_editor',
    'original_source_navigation',
    'original_update_service_through_native_bridge',
    'reopen_original_note_and_session_files',
    'return_clears_original_composer',
    'selection_chat_composers_and_citation',
    'signed_bounded_pdf_worker',
    'signed_native_window_material',
    'status_disappears_at_first_text',
    'stop_preserves_received_text',
    'waiting_status_not_clipped',
}
assert set(business['checks']) == expected_business_checks, business
assert business['checks'].get('divider_interface_language_updates') == 'passed', business
shutil.copy2(business_path, evidence / 'ci-business.json')
shutil.copy2(support / 'Results/workspace.png', evidence / 'ci-business-window.png')
for filename in ['selection-composers.png', 'selection-discussion.png', 'reasoning-composer.png']:
    shutil.copy2(support / 'Results' / filename, evidence / ('ci-' + filename))
print('14 项会话检查与 22 项业务保存重开检查通过；含原生工具栏、选区双输入框与引用定位，不替代鼠标、输入法及触控板体验验收。')

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
