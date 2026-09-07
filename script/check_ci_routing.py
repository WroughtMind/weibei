#!/usr/bin/env python3
"""验证真实工作流的任务、关键步骤、失败门槛及发布后官网刷新条件。"""
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

import yaml

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = yaml.safe_load((ROOT / '.github/workflows/pr-checks.yml').read_text())
JOBS = WORKFLOW['jobs']
PAGES = yaml.safe_load((ROOT / '.github/workflows/pages.yml').read_text())


def condition(expression, context):
    if isinstance(expression, bool):
        return expression
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
    expression = re.sub(r"'[^']*'|\btrue\b|\bfalse\b", lambda m: {'true': 'True', 'false': 'False'}.get(m[0], m[0]), expression)
    return bool(eval(expression.strip(), {'__builtins__': {}}, {}))


def selected(scopes, full=False, event='pull_request', jobs=JOBS):
    results, active_steps, pending = {}, {}, dict(jobs)
    while pending:
        for key, job in list(pending.items()):
            dependencies = job.get('needs', [])
            if isinstance(dependencies, str):
                dependencies = [dependencies]
            if any(dep not in results for dep in dependencies):
                continue
            context = {
                'github': {'event_name': event}, 'inputs': {'full_suite': full},
                'needs': {dep: {'result': results[dep], 'outputs': scopes} for dep in dependencies},
            }
            expr = job.get('if', True)
            deps_ok = all(results[dep] == 'success' for dep in dependencies)
            explicit_status = isinstance(expr, str) and ('always()' in expr or 'cancelled()' in expr)
            running = (deps_ok or explicit_status) and condition(expr, context)
            results[key] = 'success' if running else 'skipped'
            active_steps[key] = {step.get('id') for step in job.get('steps', [])
                                 if running and condition(step.get('if', True), context)}
            del pending[key]
            break
        else:
            raise AssertionError('检查任务依赖存在循环或缺失')
    return {key for key, result in results.items() if result == 'success'}, active_steps


def require_steps(jobs, steps, job, expected):
    assert job in jobs and expected <= steps[job], (job, '漏跑必要步骤', expected - steps.get(job, set()))
    assert not JOBS[job].get('continue-on-error', False)
    for step in JOBS[job]['steps']:
        if step.get('id') in expected:
            assert not step.get('continue-on-error', False), (job, step['id'], '不得忽略失败')


# 在真实 Git 差异上验证分类，不能用“官网以外全算 App”的目录规则。
with tempfile.TemporaryDirectory() as directory:
    def git(*args):
        return subprocess.check_output(['git', '-C', directory, *args], text=True).strip()
    git('init', '-q')
    git('-c', 'user.name=CI Check', '-c', 'user.email=ci@example.invalid', 'commit', '--allow-empty', '-qm', 'base')
    scenarios = [
        ('官网', ['website/style.css', '.github/workflows/pages.yml'], {'website-check'}),
        ('发布说明和设计文档', ['Docs/releases/README.md', 'DesignSystem/README.md', 'LICENSE'], set()),
        ('工具测试', ['script/homebrew/generate_cask.test.mjs'], {'tools-check'}),
        ('工具代码', ['script/check-genui-math.ts'], {'tools-check'}),
        ('检查编排', ['.github/workflows/pr-checks.yml', 'script/check_ci_routing.py'], set()),
        ('官网与应用混合', ['website/app.js', 'Sources/WeiBei/Stores/WorkspaceStore.swift'], {'website-check', 'app-check', 'intel-check'}),
        ('编辑器配置', ['tsconfig.editor.json'], {'app-check'}),
        ('安装包声明', ['PRIVACY.md'], {'release-package', 'intel-check'}),
        ('打包脚本', ['script/build_release_dmg.sh'], {'release-package', 'intel-check'}),
        ('图标生成工具', ['DesignSystem/scripts/build-icns.ts'], {'tools-check', 'release-package', 'intel-check'}),
        ('依赖清单', ['package.json'], {'tools-check', 'app-check', 'intel-check', 'release-package'}),
    ]
    for label, paths, expected in scenarios:
        base = git('rev-parse', 'HEAD')
        for name in paths:
            path = Path(directory) / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(label)
        git('add', '.')
        git('-c', 'user.name=CI Check', '-c', 'user.email=ci@example.invalid', 'commit', '-qm', label)
        output = subprocess.check_output(['bash', str(ROOT / 'script/ci_changed_scopes.sh'), base, 'HEAD'], cwd=directory, text=True)
        scopes = dict(line.split('=') for line in output.splitlines())
        jobs, steps = selected(scopes)
        assert jobs - {'scope', 'fast-check'} == expected, (label, jobs, expected)
        if scopes['code'] == 'true':
            require_steps(jobs, steps, 'app-check', {'compile', 'core', 'dev'})
            require_steps(jobs, steps, 'intel-check', {'core'})
        if scopes['editor'] == 'true':
            require_steps(jobs, steps, 'app-check', {'dependencies', 'editor'})
        if scopes['agent'] == 'true' or scopes['data_safety'] == 'true':
            require_steps(jobs, steps, 'app-check', {'safety'})
        if scopes['tools'] == 'true':
            require_steps(jobs, steps, 'tools-check', {'dependencies', 'tools'})
        if scopes['website'] == 'true':
            require_steps(jobs, steps, 'website-check', {'website'})
        if scopes['release'] == 'true':
            require_steps(jobs, steps, 'release-package', {'dependencies', 'package'})
            require_steps(jobs, steps, 'intel-check', {'dependencies', 'package'})
        if label == '官网':
            manual_jobs, manual_steps = selected(scopes, True, 'workflow_dispatch')
            assert manual_jobs == set(JOBS), '手动完整检查必须保留全部验证'
            require_steps(manual_jobs, manual_steps, 'app-check', {'compile', 'core', 'dev', 'dependencies', 'editor', 'safety'})
        print(f'{label}: 任务与必要步骤正确')

# 确认测试本身能识别“任务启动了，但实际编译被条件关闭”。
mutated = copy.deepcopy(JOBS)
compile_step = next(s for s in mutated['app-check']['steps'] if s.get('id') == 'compile')
compile_step['if'] = False
jobs, steps = selected(dict.fromkeys(['code', 'agent', 'editor', 'data_safety', 'release', 'tools', 'website'], 'true'), jobs=mutated)
try:
    require_steps(jobs, steps, 'app-check', {'compile'})
except AssertionError:
    pass
else:
    raise AssertionError('回归检查没有发现编译步骤被关闭')

# 两种架构只共享范围判断，不再先排队等另一种架构完成。
assert JOBS['app-check']['needs'] == JOBS['intel-check']['needs'] == 'scope'
# 已验证最新主线组合的 PR 合入后不再重复启动应用检查。
assert 'push' not in WORKFLOW.get('on', WORKFLOW.get(True, {}))

# 执行工作流真实汇总脚本；需要的任务 skipped 也不能被当作通过。
gate = JOBS['fast-check']
assert condition(gate['if'], {})
assert set(gate['needs']) == set(JOBS) - {'fast-check'}
outputs = dict.fromkeys(['code', 'agent', 'editor', 'data_safety', 'release', 'tools', 'website'], 'true')
for failed_job in [None, *gate['needs']]:
    for outcome in (['success'] if failed_job is None else ['failure', 'cancelled', 'skipped']):
        results = {name: {'result': 'success', 'outputs': outputs if name == 'scope' else {}} for name in gate['needs']}
        if failed_job:
            results[failed_job]['result'] = outcome
        env = {**os.environ, 'RESULTS': json.dumps(results), 'FULL_SUITE': 'false', 'EVENT_NAME': 'pull_request'}
        run = subprocess.run(['bash', '-e', '-c', gate['steps'][0]['run']], env=env, capture_output=True)
        assert (run.returncode == 0) == (failed_job is None), (failed_job, outcome)

# 发布流程成功后刷新官网，失败/取消/非主线不能触发部署。
trigger = PAGES.get('on', PAGES.get(True, {}))['workflow_run']
release = yaml.safe_load((ROOT / '.github/workflows/release.yml').read_text())
assert trigger['workflows'] == [release['name']] and trigger['types'] == ['completed']
for outcome, branch, expected in [('success', 'main', True), ('failure', 'main', False), ('cancelled', 'main', False), ('success', 'feature', False)]:
    context = {'github': {'event_name': 'workflow_run', 'event': {'workflow_run': {'conclusion': outcome, 'head_branch': branch}}}}
    assert condition(PAGES['jobs']['build']['if'], context) == expected
assert PAGES['jobs']['build']['steps'][0]['with']['ref'] == 'main'
print('编译关闭识别、并行依赖、失败门槛、发布后官网刷新: 通过')
