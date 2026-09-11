#!/usr/bin/env python3
"""Deterministic transport for the real WeiBei HTTP/Agent round trip; not a model."""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import time

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        body = json.dumps({"data": [{"id": "catalyst-local-check", "object": "model"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.headers.get("Authorization") != "Bearer catalyst-test-only":
            self.send_error(401)
            return
        size = int(self.headers.get("Content-Length", "0"))
        if not 0 < size <= 4_000_000:
            self.send_error(413)
            return
        payload = json.loads(self.rfile.read(size))
        messages = payload.get("messages", [])
        user = next((str(m.get("content", "")) for m in reversed(messages) if m.get("role") == "user"), "")
        tools = [m.get("tool_call_id") for m in messages if m.get("role") == "tool"]
        with (args.output / "requests.jsonl").open("a") as log:
            log.write(json.dumps({"path": self.path, "model": payload.get("model"), "fixture_auth": True,
                                  "roles": [m.get("role") for m in messages], "tool_results": tools,
                                  "question": user}, ensure_ascii=False) + "\n")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

        def chunk(delta, finish=None):
            value = {"id": "check452", "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            self.wfile.write(("data: " + json.dumps(value, ensure_ascii=False) + "\n\n").encode())
            self.wfile.flush()

        try:
            item = re.search(r"WB452_ITEM=(\S+)", user)
            if item and "read452" not in tools:
                chunk({"tool_calls": [{"index": 0, "id": "read452", "type": "function",
                    "function": {"name": "weibei_course_read", "arguments": json.dumps({"itemID": item[1]})}}]})
                chunk({}, "tool_calls")
            else:
                if "WB452_STOP" in user:
                    answer = "## 停止验证\n\n" + "正在输出的正文应完整保留。中文 café 👩🏽‍💻。\n\n" * 400
                    step, delay = 30, 0.06
                elif item:
                    time.sleep(2)
                    image = re.search(r"WB452_IMAGE=(\S+)", user)
                    answer = "## 资料与阅读位置\n\n这是通过原 HTTP 客户端、Agent 和资料读取工具收到的独立测试回答。\n\n"
                    read_result = next(m["content"] for m in messages if m.get("tool_call_id") == "read452")
                    for result_item in json.loads(read_result).get("items", []):
                        source = result_item.get("source") or {}
                        if label := source.get("label"):
                            answer += label + "\n\n"
                    answer += "保留第一段的显示对象，后续内容增长时继续读取同一段。\n\n"
                    answer += "行内公式 $E=mc^2$。\n\n$$\\int_0^1 x^2\\,dx=\\frac{1}{3}$$\n\n"
                    answer += "```swift\nlet 原始业务 = [\"资料\", \"会话\", \"笔记\"]\nprint(原始业务)\n```\n\n"
                    answer += "|操作|结果|\n|---|---|\n|读取|原资料工具|\n|保存|原笔记写入通道|\n\n"
                    if image:
                        answer += f"![候选独立图片]({image[1]})\n\n"
                    answer += "### 长正文\n\n" + "\n\n".join(f"第 {n+1} 段。保存来源、理解和阅读位置，不因继续输出丢失已经看过的文字。" for n in range(30))
                    answer += "\n\n【候选真实业务链路结束】"
                    step, delay = 40, 0.05
                else:
                    # The original runtime also requests a concise session title.
                    answer, step, delay = "候选阅读位置验证", 40, 0
                for offset in range(0, len(answer), step):
                    chunk({"content": answer[offset:offset + step]})
                    time.sleep(delay)
                chunk({}, "stop")
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            with (args.output / "requests.jsonl").open("a") as log:
                log.write(json.dumps({"client_cancelled": True}) + "\n")


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
endpoint = f"http://127.0.0.1:{server.server_port}/v1"
(args.output / "endpoint.txt").write_text(endpoint)
print(endpoint, flush=True)
server.serve_forever()
