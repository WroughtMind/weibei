#!/usr/bin/env python3
"""Temporary observation of the isolated runner's Python permission prompt."""
import datetime
import http.server
import json
import os
import platform
from pathlib import Path
import runpy
import socket
import socketserver
import subprocess
import sys
import time

if not (os.environ.get("CI") == "true" and os.environ.get("GITHUB_ACTIONS") == "true"
        and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"
        and os.environ.get("RUNNER_OS") == "macOS" and platform.machine() == "arm64"):
    raise SystemExit("only the isolated hosted ARM runner may run this diagnostic")
mode = sys.argv[1]
if mode not in ("original", "no-dns"):
    raise SystemExit("unknown diagnostic mode")
output = Path("App/Evidence/ci-network-" + mode)
output.mkdir(parents=True, exist_ok=True)

if len(sys.argv) > 2 and sys.argv[2] == "worker":
    def record(event, **fields):
        print(json.dumps({"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                          "monotonic": time.monotonic(), "pid": os.getpid(),
                          "event": event, **fields}, default=repr), file=sys.stderr, flush=True)

    def observe(name):
        original = getattr(socket, name)
        def wrapped(*args, **kwargs):
            record(name + ".begin", args=args, kwargs=kwargs)
            try:
                result = original(*args, **kwargs)
            except Exception as error:
                record(name + ".error", error=repr(error))
                raise
            record(name + ".end", result=result)
            return result
        setattr(socket, name, wrapped)

    observe("getfqdn")
    observe("gethostbyaddr")

    class ObservedServer(http.server.ThreadingHTTPServer):
        def server_bind(self):
            record("bind.begin", address=self.server_address)
            if mode == "original":
                super().server_bind()
            else:
                socketserver.TCPServer.server_bind(self)
                self.server_name, self.server_port = self.server_address[:2]
            record("bind.end", address=self.socket.getsockname(), server_name=self.server_name)

    http.server.ThreadingHTTPServer = ObservedServer
    record("start", mode=mode, executable=sys.executable, version=sys.version, ppid=os.getppid())
    target = Path("App/script/business-server.py")
    sys.argv = [str(target), "--output", str(output)]
    runpy.run_path(str(target), run_name="__main__")
else:
    def screenshot(name):
        subprocess.run(["/usr/sbin/screencapture", "-x", str(output / (name + ".png"))], check=True)

    screenshot("before")
    log_start = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with (output / "resolver.log").open("w") as log:
        worker = subprocess.Popen([sys.executable, __file__, mode, "worker"], stdout=log, stderr=log)
        try:
            started = time.monotonic()
            for seconds in (2, 10, 20, 30):
                time.sleep(max(0, started + seconds - time.monotonic()))
                screenshot("after-" + str(seconds))
            with (output / "listener.log").open("w") as listener:
                result = subprocess.run(["lsof", "-nP", "-a", "-p", str(worker.pid), "-iTCP"],
                                        stdout=listener, stderr=subprocess.STDOUT)
                listener.write("\nexit=" + str(result.returncode) + "\n")
            endpoint_file = output / "endpoint.txt"
            endpoint = endpoint_file.read_text().strip() if endpoint_file.exists() else None
            if not endpoint or not endpoint.startswith("http://127.0.0.1:"):
                raise RuntimeError("numeric loopback endpoint not ready: " + str(endpoint))
            response = subprocess.check_output(["curl", "--fail", "--silent", "--show-error", "--noproxy", "*",
                                                "--max-time", "10", "-H", "Authorization: Bearer catalyst-test-only",
                                                endpoint + "/models"], text=True)
            (output / "health.json").write_text(response)
        finally:
            worker.terminate()
            try:
                worker.wait(timeout=10)
            except subprocess.TimeoutExpired:
                worker.kill()
                worker.wait(timeout=5)
            with (output / "system.log").open("w") as system:
                subprocess.run(["/usr/bin/log", "show", "--start", log_start, "--style", "compact", "--info",
                                "--predicate", '(process == "tccd" OR process == "mDNSResponder" OR '
                                'subsystem CONTAINS[c] "localnetwork" OR process == "Python")'],
                               stdout=system, stderr=subprocess.STDOUT, timeout=20, check=True)
    print(json.dumps({"mode": mode, "evidence": str(output), "status": "observed"}))
