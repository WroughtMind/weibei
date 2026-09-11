#!/usr/bin/env bash
set -euo pipefail
# Real windows are permitted only on the isolated CI desktop.
[[ "${CI:-}" == true ]] || { echo '本机候选请在画中画验收。' >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/weibei-business-ci.XXXXXX")"
python3 App/script/business-server.py --output "$CHECK_DIR" > "$CHECK_DIR/server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
for _ in {1..100}; do
  [[ ! -s "$CHECK_DIR/endpoint.txt" ]] || break
  kill -0 "$server_pid"
  sleep 0.1
done
export WEIBEI_BUSINESS_CHECK_ENDPOINT="$(cat "$CHECK_DIR/endpoint.txt")"
export WEIBEI_BUNDLE_IDENTIFIER="com.changfenhuang.weibei.ci.$(uuidgen | tr '[:upper:]' '[:lower:]').businesscheck"
export WEIBEI_ACCEPTANCE_CHECKS=1
./script/build_and_run.sh package
export CHECK_APP="$ROOT/dist/acceptance/魏碑.app"
export CHECK_SUPPORT="$HOME/Library/Application Support/$WEIBEI_BUNDLE_IDENTIFIER"
export CHECK_SOURCE="$(git rev-parse HEAD)"
mkdir -p App/Evidence
python3 - <<'PY'
import json, os, shutil, subprocess
from pathlib import Path
app = os.environ['CHECK_APP']
support = Path(os.environ['CHECK_SUPPORT'])
source = os.environ['CHECK_SOURCE']
evidence = Path('App/Evidence')

def launch(argument):
    subprocess.run(['open', '-n', '-W', app, '--args', argument], check=True, timeout=360)

def verify(path, source_key):
    result = json.loads(path.read_text())
    assert result[source_key] == source and result['source_dirty'] is False, result
    assert result['platform'] == 'Mac Catalyst', result
    assert result['checks'] and all(v == 'passed' for v in result['checks'].values()), result
    return result

launch('--self-check')
conversation = verify(support / 'Results/latest.json', 'source_revision')
assert conversation['idiom'] == 'mac' and len(conversation['checks']) == 11, conversation
for filename in ['latest.json', 'window.png', 'diagram.png']:
    shutil.copy2(support / 'Results' / filename, evidence / ('ci-conversation-' + filename))

business_path = support / 'Workspace/business-check.json'
launch('--exit-after-check')
assert verify(business_path, 'source')['status'] == 'awaiting_reopen'
launch('--exit-after-check')
business = verify(business_path, 'source')
assert business['status'] == 'passed' and len(business['checks']) == 19, business
shutil.copy2(business_path, evidence / 'ci-business.json')
shutil.copy2(support / 'Results/workspace.png', evidence / 'ci-business-window.png')
print('11 项会话检查与 19 项原业务保存重开检查通过；不替代鼠标、输入法及触控板体验验收。')
PY
