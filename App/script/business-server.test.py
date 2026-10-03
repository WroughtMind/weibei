#!/usr/bin/env python3
"""Exercise the real fixture handler with in-memory HTTP streams; no sockets."""
import io
import json
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch


class FixtureServer:
    server_port = 0

    def __init__(self, address, handler):
        assert address == ("127.0.0.1", 0)

    def serve_forever(self):
        pass


class BusinessFixtureTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="weibei-fixture-test-")
        self.addCleanup(self.scratch.cleanup)
        server = Path(__file__).with_name("business-server.py")
        with patch("http.server.ThreadingHTTPServer", FixtureServer), patch("sys.argv", [str(server), "--output", self.scratch.name]):
            self.fixture = runpy.run_path(str(server))
        self.fixture["answer_ready"].set()

    def request(self, messages):
        body = json.dumps({"model": "catalyst-local-check", "messages": messages}).encode()
        handler = object.__new__(self.fixture["Handler"])
        handler.path = "/v1/chat/completions"
        handler.headers = {"Authorization": "Bearer catalyst-test-only", "Content-Length": str(len(body))}
        handler.rfile = io.BytesIO(body)
        handler.wfile = io.BytesIO()
        handler.send_response = lambda status: self.assertEqual(status, 200)
        handler.send_header = lambda *_: None
        handler.end_headers = lambda: None
        with patch("time.sleep", lambda _: None):
            handler.do_POST()
        stream = handler.wfile.getvalue().decode()
        self.assertTrue(stream.endswith("data: [DONE]\n\n"))
        return [json.loads(line.removeprefix("data: "))["choices"][0]
                for line in stream.splitlines() if line.startswith("data: ") and line != "data: [DONE]"]

    def test_floating_round_trip_renders_diagram_between_native_math_and_tail(self):
        user = {"role": "user", "content": "解释选区 WB452_ITEM=synthetic-material WB514_FLOATING_RICH"}
        first = self.request([user])
        read = first[0]["delta"]["tool_calls"][0]
        self.assertEqual(read["function"]["name"], "weibei_course_read")
        self.assertEqual(json.loads(read["function"]["arguments"]), {"itemID": "synthetic-material"})
        read_result = {"role": "tool", "tool_call_id": "read452", "content": '{"items": []}'}
        second = self.request([user, read_result])
        math = second[0]["delta"]["content"]
        self.assertIn("WB514_FLOATING_BODY", math)
        self.assertIn("$x+1$", math)
        self.assertIn("$$\\frac{1}{2}+\\frac{1}{2}=1$$", math)
        render = second[1]["delta"]["tool_calls"][0]
        self.assertEqual(render["id"], "floating514")
        self.assertEqual(render["function"]["name"], "render_ui")
        arguments = json.loads(render["function"]["arguments"])
        self.assertEqual(arguments["id"], "floating-compact-diagram")
        self.assertEqual(arguments["spec"]["items"], [{"type": "mermaid", "code": "graph LR\nA[WB514_START] --> B[WB514_END]"}])
        self.assertEqual(second[-1]["finish_reason"], "tool_calls")
        displayed = {"role": "tool", "tool_call_id": "floating514", "content": "互动界面已显示"}
        third = self.request([user, read_result, displayed])
        tail = "".join(chunk["delta"].get("content", "") for chunk in third)
        self.assertIn("【候选真实业务链路结束】", tail)
        self.assertNotIn("长正文", math + tail)
        self.assertFalse(any("tool_calls" in chunk["delta"] for chunk in third))

    def test_main_round_trip_keeps_its_long_answer_image_code_and_table(self):
        user = {"role": "user", "content": "读取资料 WB452_ITEM=synthetic-material WB452_IMAGE=file:///synthetic.png"}
        read_result = {"role": "tool", "tool_call_id": "read452", "content": '{"items": [{"source": {"label": "独立资料"}}]}'}
        chunks = self.request([user, read_result])
        answer = "".join(chunk["delta"].get("content", "") for chunk in chunks)
        for expected in ["独立资料", "$E=mc^2$", "```swift", "|操作|结果|", "file:///synthetic.png", "第 30 段", "【候选真实业务链路结束】"]:
            self.assertIn(expected, answer)
        self.assertNotIn("WB514_FLOATING_BODY", answer)
        self.assertFalse(any("tool_calls" in chunk["delta"] for chunk in chunks))

    def test_model_catalog_requires_the_same_credential_as_chat(self):
        for key, expected in [(None, 401), ("Bearer wrong", 401), ("Bearer catalyst-test-only", 200)]:
            with self.subTest(key=key):
                handler = object.__new__(self.fixture["Handler"])
                handler.path = "/v1/models"
                handler.headers = {"Authorization": key}
                handler.wfile = io.BytesIO()
                statuses = []
                handler.send_response = handler.send_error = statuses.append
                handler.send_header = lambda *_: None
                handler.end_headers = lambda: None
                handler.do_GET()
                self.assertEqual(statuses, [expected])
                if expected == 200:
                    self.assertEqual(json.loads(handler.wfile.getvalue())["data"][0]["id"], "catalyst-local-check")


if __name__ == "__main__":
    unittest.main()
