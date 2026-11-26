#!/usr/bin/env python3
"""Reuse two successful Catalyst checks only for identical native inputs."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import urlencode


ROOT = Path(__file__).resolve().parents[1]
EDITOR_HARNESS = b'Sources/WeiBeiWebEditorCheck/main.swift'
TEST_ONLY_DIRECTORIES = (
    b'Sources/WeiBei/WebEditor/test/',
    b'Sources/WeiBeiWebEditorCheck/',
    b'Sources/WeiBeiSelfCheck/',
    b'Sources/WeiBeiNativeCheck/',
    b'Tests/WeiBeiSafetyTests/',
)
TEST_ONLY_FILES = {
    b'script/check_build_info.swift',
    b'script/check_build_number.py',
    b'script/check_ci_routing.py',
    b'script/homebrew/generate_cask.test.mjs',
    b'script/packed_web_script.test.mjs',
    b'script/test_ci_native_reuse.py',
    b'script/test_release_flow.py',
}
STAMP = '验证当前架构工具链与源码 '
RUNNERS = {'arm64': 'macos-26', 'x86_64': 'macos-26-intel'}


def native_input_key(root, revision):
    # Hash the tested merge tree, including paths, executable bits, toolchain
    # declarations and lockfiles. Everything outside test-only targets stays in.
    tree = subprocess.check_output(['git', 'ls-tree', '-rz', '--full-tree', revision], cwd=root)
    digest = hashlib.sha256()
    shared_probes = None
    for entry in tree.rstrip(b'\0').split(b'\0'):
        metadata, path = entry.split(b'\t', 1)
        if path == EDITOR_HARNESS:
            mode, _, blob = metadata.split()
            if mode not in (b'100644', b'100755'):
                raise ValueError('The editor harness must be a regular file')
            swift = subprocess.check_output(['git', 'cat-file', 'blob', blob.decode()], cwd=root)
            shared_probes = subprocess.check_output(['node', '--input-type=module', '-e', '''
                import {readFileSync} from 'node:fs';
                import {pathToFileURL} from 'node:url';
                const {genuiMeasurementObserver, genuiLabelGeometry} = await import(pathToFileURL(process.argv[1]));
                const source = readFileSync(0, 'utf8');
                process.stdout.write(JSON.stringify([genuiMeasurementObserver(source), genuiLabelGeometry(source)]));
            ''', str(ROOT / 'App/script/editor-probe-programs.mjs')], input=swift, stderr=subprocess.PIPE)
            digest.update(mode + b'\t' + path + b'\0')
        elif path not in TEST_ONLY_FILES and not path.startswith(TEST_ONLY_DIRECTORIES):
            digest.update(entry + b'\0')
    if shared_probes is None:
        raise ValueError('Missing editor harness for Catalyst acceptance')
    digest.update(shared_probes)
    return digest.hexdigest()


def prior_native_run(api, pr, run_number, key, acceptance, release):
    repo_id = pr['base']['repo']['id']
    if pr['head']['repo']['id'] != repo_id:
        return None

    stamp = STAMP + key
    required = {stamp, '通过唯一入口构建正式 Catalyst 应用', '逐架构验证正式应用启动'}
    if acceptance:
        required.update({'记录系统原生全屏对照', '在当前架构的真实 Catalyst 进程检查会话', '确认未重复编译验收依赖'})
    if release:
        required.add('生成并挂载验收当前架构安装包')

    query = urlencode({'event': 'pull_request', 'status': 'completed', 'branch': pr['head']['ref'], 'per_page': 100})
    runs = api(f'actions/workflows/pr-checks.yml/runs?{query}', 'workflow_runs')
    job_names = {f'Catalyst {arch} 构建、会话与安装包': runner for arch, runner in RUNNERS.items()}
    for run in sorted(runs, key=lambda item: item['run_number'], reverse=True):
        if (run['run_number'] >= run_number or (run.get('head_repository') or {}).get('id') != repo_id
                or not any(pull['number'] == pr['number'] for pull in run['pull_requests'])):
            continue
        run_id = run['id']
        if not isinstance(run_id, int) or run_id <= 0:
            continue
        jobs = api(f'actions/runs/{run_id}/jobs?filter=all&per_page=100', 'jobs')
        latest = {}
        for job in jobs:
            name = job['name']
            if name in job_names and (name not in latest or job['run_attempt'] > latest[name]['run_attempt']):
                latest[name] = job

        # An earlier reuse or a run on different inputs has no matching stamp.
        if not any(step['name'] == stamp for job in latest.values() for step in job.get('steps') or []):
            continue
        if all(
            name in latest and latest[name]['conclusion'] == 'success' and runner in latest[name]['labels']
            and required <= {step['name'] for step in latest[name]['steps'] if step['conclusion'] == 'success'}
            for name, runner in job_names.items()
        ):
            return run_id
        return None
    return None


def main():
    try:
        sha = os.environ['GITHUB_SHA']
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        if head != sha:
            raise ValueError('The checkout differs from the tested revision')
        key = native_input_key(ROOT, sha)
    except (KeyError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f'无法核验双架构输入，正常运行双架构检查（{type(exc).__name__}）')
        return

    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        print(f'key={key}', file=output)

    repository = os.environ['GITHUB_REPOSITORY']
    deadline = time.monotonic() + 20

    def api(endpoint, field):
        pages = json.loads(subprocess.check_output(
            ['gh', 'api', '--paginate', '--slurp', f'repos/{repository}/{endpoint}'],
            timeout=max(0, deadline - time.monotonic()),
        ))
        return [record for page in pages for record in page[field]]

    try:
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        run_id = prior_native_run(api, event['pull_request'], int(os.environ['GITHUB_RUN_NUMBER']), key,
                                  os.environ['NATIVE_ACCEPTANCE'] == 'true', os.environ['NATIVE_RELEASE'] == 'true')
    except (KeyError, OSError, TypeError, ValueError, subprocess.SubprocessError) as exc:
        print(f'无法读取上轮结果，正常运行双架构检查（{type(exc).__name__}）')
        return
    if run_id is not None:
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            print(f'双架构构建与验收输入相同，复用 [CI #{run_id}]({os.environ["GITHUB_SERVER_URL"]}/{repository}/actions/runs/{run_id}) '
                  '中 Apple 芯片和 Intel 均通过的结果。', file=summary)
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            print(f'reused_run={run_id}', file=output)


if __name__ == '__main__':
    main()
