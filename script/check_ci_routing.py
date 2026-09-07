#!/usr/bin/env python3
"""官网不能启动 Mac；应用检查不能漏跑；失败不能通过合并门槛。"""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

import yaml

ROOT = Path(__file__).resolve().parent.parent
JOBS = yaml.safe_load((ROOT / '.github/workflows/pr-checks.yml').read_text())['jobs']


def condition(expression, context):
    """求值本工作流用到的布尔条件；不支持的语法直接报错。"""
    expression = expression.removeprefix('${{').removesuffix('}}').strip()
    def value(match):
        result = context
        for part in match[0].split('.'):
            result = result[part]
        return repr(result)
    expression = re.sub(r'\b(?:github|needs|steps|inputs)(?:\.[\w-]+)+', value, expression)
    expression = expression.replace('always()', 'True').replace('cancelled()', 'False')
    expression = expression.replace('&&', ' and ').replace('||', ' or ')
    expression = re.sub(r'!(?!=)', ' not ', expression)
    return bool(eval(expression.strip(), {'__builtins__': {}}, {}))


def selected_jobs(event, scopes, full=False):
    results = {}
    pending = dict(JOBS)
    while pending:
        for key, job in list(pending.items()):
            dependencies = job.get('needs', [])
            if isinstance(dependencies, str):
                dependencies = [dependencies]
            if any(dep not in results for dep in dependencies):
                continue
            context = {
                'github': {'event_name': event}, 'inputs': {'full_suite': full},
                'steps': {'scope': {'outputs': scopes}},
                'needs': {dep: {'result': results[dep], 'outputs': scopes} for dep in dependencies},
            }
            expr = job.get('if', 'True')
            # GitHub 默认在依赖跳过时跳过下游，显式状态函数才覆盖此行为。
            deps_ok = all(results[dep] == 'success' for dep in dependencies)
            explicit_status = 'always()' in expr or 'cancelled()' in expr
            results[key] = 'success' if (deps_ok or explicit_status) and condition(expr, context) else 'skipped'
            del pending[key]
            break
        else:
            raise AssertionError('检查任务依赖存在循环或缺失')
    return {key for key, result in results.items()
            if result == 'success' and JOBS[key]['runs-on'].startswith('macos')}


with tempfile.TemporaryDirectory() as directory:
    def git(*args):
        return subprocess.check_output(['git', '-C', directory, *args], text=True).strip()
    git('init', '-q')
    git('-c', 'user.name=CI Check', '-c', 'user.email=ci@example.invalid', 'commit', '--allow-empty', '-qm', 'base')
    scenarios = [
        ('官网', ['website/style.css', '.github/workflows/pages.yml'], set(), set()),
        ('说明文档', ['README.md'], set(), set()),
        ('检查规则', ['.github/workflows/pr-checks.yml', 'script/ci_changed_scopes.sh', 'script/check_ci_routing.py'], set(), set()),
        ('官网与应用混合', ['website/app.js', 'Sources/WeiBei/Stores/WorkspaceStore.swift'], {'app-check', 'intel-check'}, {'app-check', 'intel-check'}),
        ('仅编辑器配置', ['tsconfig.editor.json'], {'app-check'}, {'app-check'}),
        ('安装包声明', ['LICENSE'], {'release-package', 'intel-check'}, set()),
        ('发布流程', ['.github/workflows/release.yml'], {'app-check', 'intel-check', 'release-package'}, {'app-check', 'intel-check'}),
    ]
    for label, paths, pr_jobs, push_jobs in scenarios:
        base = git('rev-parse', 'HEAD')
        for name in paths:
            path = Path(directory) / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(label)
        git('add', '.')
        git('-c', 'user.name=CI Check', '-c', 'user.email=ci@example.invalid', 'commit', '-qm', label)
        output = subprocess.check_output(['bash', str(ROOT / 'script/ci_changed_scopes.sh'), base, 'HEAD'], cwd=directory, text=True)
        scopes = dict(line.split('=') for line in output.splitlines())
        for event, expected in [('pull_request', pr_jobs), ('push', push_jobs)]:
            actual = selected_jobs(event, scopes)
            assert actual == expected, (label, event, actual, expected)
        if label == '官网':
            assert selected_jobs('workflow_dispatch', scopes) == {'app-check', 'intel-check'}
            assert selected_jobs('workflow_dispatch', scopes, True) == {'app-check', 'intel-check', 'release-package'}
        print(f'{label}: 合并前/后检查范围正确')

# 执行工作流真实的汇总脚本，确保失败和取消不会被当作成功。
gate = JOBS['fast-check']
assert condition(gate['if'], {}), '必需检查必须始终报告结果'
for failed_job in [None, *gate['needs']]:
    for outcome in (['success'] if failed_job is None else ['failure', 'cancelled']):
        results = {name: {'result': 'success' if name == 'scope' else 'skipped'} for name in gate['needs']}
        if failed_job:
            results[failed_job]['result'] = outcome
        run = subprocess.run(['bash', '-e', '-c', gate['steps'][0]['run']], env={**os.environ, 'RESULTS': json.dumps(results)}, capture_output=True)
        assert (run.returncode == 0) == (failed_job is None), (failed_job, outcome)
print('必需检查: 相关任务失败或取消均阻止通过')
