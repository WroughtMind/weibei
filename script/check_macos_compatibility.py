#!/usr/bin/env python3
"""Run a released app only on an isolated GitHub-hosted macOS desktop."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time


def command(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def app_pid(binary):
    processes = command('ps', '-axo', 'pid=,command=')
    return next((int(line.strip().split(None, 1)[0]) for line in processes.splitlines()
                 if len(line.strip().split(None, 1)) == 2
                 and (line.strip().split(None, 1)[1] == str(binary)
                      or line.strip().split(None, 1)[1].startswith(str(binary) + ' '))), None)


def main():
    if not (os.environ.get('CI') == 'true'
            and os.environ.get('GITHUB_ACTIONS') == 'true'
            and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted'):
        raise SystemExit('This check requires an isolated GitHub-hosted desktop.')
    app, evidence, probe = (Path(p).resolve() for p in sys.argv[1:])
    evidence.mkdir(parents=True, exist_ok=True)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    started = time.time()
    result = {'status': 'running', 'os': command('sw_vers'), 'arch': command('uname', '-m'),
              'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
              'source': info.get('WeiBeiGitCommit'), 'rounds': []}
    pid = None
    try:
        assert app_pid(binary) is None, 'Candidate is already running'
        for phase in ('cold_start', 'reopen'):
            console = evidence / (phase + '.log')
            subprocess.run(['open', '-n', str(app), '--stdout', str(console), '--stderr', str(console)], check=True)
            deadline = time.monotonic() + 30
            state = None
            while time.monotonic() < deadline:
                pid = app_pid(binary)
                if pid:
                    inspected = subprocess.run([str(probe), 'inspect', str(pid)], capture_output=True, text=True)
                    if inspected.returncode == 0:
                        state = json.loads(inspected.stdout)
                        if state['finished_launching'] and state['visible_windows']:
                            break
                time.sleep(0.25)
            assert pid and state and state['finished_launching'] and state['visible_windows'], 'App did not present a window'
            # Allow deferred library initialization and update observation to run.
            time.sleep(5)
            assert app_pid(binary) == pid, 'App exited after presenting its first window'
            subprocess.run(['screencapture', '-x', str(evidence / (phase + '.png'))], check=True)
            subprocess.run([str(probe), 'quit', str(pid)], check=True)
            deadline = time.monotonic() + 30
            while app_pid(binary) and time.monotonic() < deadline:
                time.sleep(0.25)
            assert app_pid(binary) is None, 'App did not finish a normal Quit'
            pid = None
            result['rounds'].append({'phase': phase, 'window_state': state, 'quit': 'completed'})
        result['status'] = 'passed'
    except Exception as error:
        result['status'] = 'failed'
        result['error'] = str(error)
        raise
    finally:
        if pid and app_pid(binary) == pid:
            subprocess.run(['kill', '-TERM', str(pid)], check=False)
        # Crash delivery can lag behind process termination.
        time.sleep(3)
        reports = []
        for directory in (Path.home() / 'Library/Logs/DiagnosticReports', Path('/Library/Logs/DiagnosticReports')):
            if directory.exists():
                for report in directory.glob('WeiBei*'):
                    if report.is_file() and report.stat().st_mtime >= started:
                        shutil.copy2(report, evidence / report.name)
                        reports.append(report.name)
        result['crash_reports'] = reports
        if reports and result['status'] == 'passed':
            result['status'] = 'failed'
            result['error'] = 'New crash report appeared during launch/quit'
        (evidence / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
        with (evidence / 'system.log').open('w') as log:
            subprocess.run(['/usr/bin/log', 'show', '--last', '3m', '--style', 'compact',
                            '--predicate', 'process == "WeiBei" OR eventMessage CONTAINS "WeiBeiWindowBridge"'],
                           stdout=log, stderr=subprocess.STDOUT, check=False)
    if result['status'] != 'passed':
        raise SystemExit(result.get('error', 'Compatibility check failed'))
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
