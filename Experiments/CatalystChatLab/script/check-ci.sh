#!/bin/bash
set -euo pipefail
# This opens a real window. Local desktop checks use the in-app button through
# picture-in-picture; the command is restricted to the isolated CI desktop.
[[ "${CI:-}" == "true" ]] || { echo '请在画中画窗口使用“运行必要行为检查”。'; exit 1; }
lab_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$lab_dir"
open -W "$lab_dir/dist/魏碑-Catalyst独立候选.app" --args --self-check
mkdir -p Evidence
cp "$HOME/Library/Application Support/org.weibei.CatalystChatLab/Results/latest.json" Evidence/ci.json
cp "$HOME/Library/Application Support/org.weibei.CatalystChatLab/Results/window.png" Evidence/ci-window.png
cp "$HOME/Library/Application Support/org.weibei.CatalystChatLab/Results/diagram.png" Evidence/ci-diagram.png
python3 - <<'PY'
import json
from pathlib import Path
result = json.loads(Path('Evidence/ci.json').read_text())
assert result['platform'] == 'Mac Catalyst' and result['idiom'] == 'mac'
assert len(result['checks']) == 10 and all(value == 'passed' for value in result['checks'].values()), result['checks']
print('10 项实际 Catalyst 进程内的会话行为检查通过。CI 不代表鼠标、输入法或用户手感验收。')
PY
