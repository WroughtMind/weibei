#!/usr/bin/env python3
"""Regression checks for the native input stamp and its merge-gate evidence."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from ci_native_reuse import EDITOR_HARNESS, RUNNERS, STAMP, native_input_key, prior_native_run


HARNESS = '''
    private static let genuiMeasurementObserver = #"""
        observer();
    """#

    private func verifyGenuiLabelGeometry() {
        let script = """
        geometry();
        """
    }
'''


class NativeInputKeyTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.git('init', '-q')
        self.harness = EDITOR_HARNESS.decode()
        self.initial = self.commit({self.harness: HARNESS, 'App/Sources/App.swift': 'initial app source'})

    def git(self, *args):
        return subprocess.check_output(
            ['git', '-c', 'user.name=CI Check', '-c', 'user.email=ci@example.invalid', *args], cwd=self.root, text=True,
        ).strip()

    def commit(self, files):
        for name, content in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        return native_input_key(self.root, 'HEAD')

    def test_independent_editor_only_changes_keep_key(self):
        result = self.commit({
            self.harness: HARNESS + '// Change editor harness readiness only.',
            'Sources/WeiBei/WebEditor/test/ready.test.ts': 'an independent editor assertion',
            'script/homebrew/generate_cask.test.mjs': 'an independent tools assertion',
        })
        self.assertEqual(self.initial, result)

    def test_shared_editor_probes_change_key(self):
        for probe in ('observer', 'geometry'):
            with self.subTest(probe=probe):
                result = self.commit({self.harness: HARNESS.replace(f'{probe}();', f'{probe}(fixture);')})
                self.assertNotEqual(self.initial, result)

    def test_missing_probe_has_no_key(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.commit({self.harness: HARNESS.replace('genuiMeasurementObserver', 'differentName')})

    def test_merge_tree_includes_current_base_and_native_inputs(self):
        base = self.git('rev-parse', 'HEAD')
        self.git('switch', '-qc', 'editor-tests')
        self.assertEqual(self.initial, self.commit({self.harness: HARNESS + '// new editor test'}))
        self.git('switch', '-q', '--detach', base)
        changed = self.commit({'App/UITests/Smoke.swift': 'a new native acceptance assertion'})
        self.git('merge', '-q', '--no-ff', '--no-edit', 'editor-tests')
        self.assertEqual(changed, native_input_key(self.root, 'HEAD'))
        self.assertNotEqual(self.initial, changed)

    def test_lockfiles_and_application_files_have_different_keys(self):
        for path in ('package-lock.json', 'App/Sources/App.swift', '.github/workflows/pr-checks.yml', 'App/script/check-ci.sh'):
            with self.subTest(path=path):
                previous = native_input_key(self.root, 'HEAD')
                self.assertNotEqual(previous, self.commit({path: f'new contents for {path}'}))


class NativeRunTests(unittest.TestCase):
    def setUp(self):
        self.pr = {'number': 72, 'base': {'repo': {'id': 1}}, 'head': {'ref': 'ci/editor-test', 'repo': {'id': 1}}}
        self.key = 'a' * 64
        self.runs = [dict(id=71, run_number=71, head_repository={'id': 1}, pull_requests=[{'number': 72}], conclusion='failure')]
        self.steps = [
            STAMP + self.key, '通过唯一入口构建正式 Catalyst 应用', '逐架构验证正式应用启动',
            '记录系统原生全屏对照', '在当前架构的真实 Catalyst 进程检查会话', '确认未重复编译验收依赖',
            '生成并挂载验收当前架构安装包',
        ]
        self.jobs = {71: [self.job(arch, runner) for arch, runner in RUNNERS.items()]}

    def job(self, arch, runner, attempt=1, result='success'):
        return {'name': f'Catalyst {arch} 构建、会话与安装包', 'labels': [runner], 'run_attempt': attempt,
                'conclusion': result, 'steps': [{'name': step, 'conclusion': 'success'} for step in self.steps]}

    def find_run(self, acceptance=True, release=True):
        def api(endpoint, field):
            if field == 'workflow_runs':
                self.assertIn('branch=ci%2Feditor-test', endpoint)
                return self.runs
            self.assertIn('filter=all', endpoint)
            return self.jobs[int(endpoint.split('/')[2])]
        return prior_native_run(api, self.pr, 74, self.key, acceptance, release)

    def test_uses_passed_native_jobs_even_after_editor_failure_or_reuse(self):
        self.runs.append({**self.runs[0], 'id': 72, 'run_number': 72})
        self.jobs[72] = []
        self.assertEqual(self.find_run(), 71)

    def test_different_inputs_wrong_pr_or_one_architecture_are_insufficient(self):
        self.key = 'b' * 64
        self.assertIsNone(self.find_run())
        self.key = 'a' * 64
        self.runs[0]['pull_requests'] = [{'number': 70}]
        self.assertIsNone(self.find_run())
        self.runs[0]['pull_requests'] = [{'number': 72}]
        self.jobs[71].pop()
        self.assertIsNone(self.find_run())

    def test_package_and_native_acceptance_must_have_run_when_required(self):
        self.jobs[71][1]['steps'][-1]['conclusion'] = 'skipped'
        self.assertIsNone(self.find_run())
        self.assertEqual(self.find_run(release=False), 71)
        self.jobs[71][1]['steps'][3]['conclusion'] = 'skipped'
        self.assertIsNone(self.find_run(release=False))
        self.assertEqual(self.find_run(acceptance=False, release=False), 71)

    def test_more_recent_failed_attempt_invalidates_older_success(self):
        self.jobs[71].append(self.job('arm64', RUNNERS['arm64'], attempt=2, result='failure'))
        self.assertIsNone(self.find_run())


if __name__ == '__main__':
    unittest.main()
