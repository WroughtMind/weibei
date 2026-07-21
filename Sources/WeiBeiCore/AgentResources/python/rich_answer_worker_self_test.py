#!/usr/bin/env python3
"""Self tests for the controlled rich-answer Python worker."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


WORKER = Path(__file__).with_name("rich_answer_worker.py")


def base_request(operation: str, data: dict[str, Any], parameters: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "requestID": f"test-{operation}",
        "operation": operation,
        "data": data,
        "parameters": parameters or {},
        "requestedOutput": {
            "id": "artifact-1",
            "kind": "json_spec",
            "mimeType": "application/json",
            "role": "analysis",
        },
        "limits": {
            "maxInputBytes": 256000,
            "maxOutputBytes": 512000,
            "maxRows": 2000,
            "maxColumns": 80,
            "maxRuntimeMS": 3000,
        },
        "sourceEvidenceIDs": ["[材料：受控计算测试]"],
    }


def call_worker(request: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    completed = subprocess.run(
        [sys.executable, "-B", str(WORKER)],
        input=json.dumps(request, ensure_ascii=False).encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.stderr:
        raise AssertionError(f"worker wrote to stderr: {completed.stderr.decode('utf-8', errors='replace')}")
    try:
        response = json.loads(completed.stdout.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise AssertionError(f"worker did not write JSON: {completed.stdout!r}") from error
    return completed.returncode, response


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_ok(request: dict[str, Any]) -> dict[str, Any]:
    code, response = call_worker(request)
    require(code == 0, f"expected success exit code, got {code}: {response}")
    require(response.get("schemaVersion") == 1, "missing schemaVersion")
    require(response.get("ok") is True, f"expected ok response: {response}")
    require(response.get("workerVersion") == "1.0.0", "wrong workerVersion")
    require(len(response.get("artifacts", [])) == 1, "expected one artifact")
    artifact = response["artifacts"][0]
    require(len(artifact.get("sha256", "")) == 64, "artifact hash missing")
    require(artifact.get("sizeBytes", 0) > 0, "artifact size missing")
    require(artifact.get("sourceEvidenceIDs") == ["[材料：受控计算测试]"], "source evidence not retained")
    payload_json = artifact.get("payloadCanonicalJSON")
    require(isinstance(payload_json, str), "canonical payload bytes missing")
    require(json.loads(payload_json) == artifact.get("payload"), "canonical payload differs from payload")
    require(
        hashlib.sha256(payload_json.encode("utf-8")).hexdigest() == artifact.get("sha256"),
        "canonical payload hash mismatch",
    )
    return response


def require_error(request: dict[str, Any], expected_code: str) -> dict[str, Any]:
    code, response = call_worker(request)
    require(code != 0, "expected non-zero exit code")
    require(response.get("schemaVersion") == 1, "missing schemaVersion on error")
    require(response.get("ok") is False, f"expected error response: {response}")
    require(response.get("error", {}).get("code") == expected_code, f"wrong error code: {response}")
    require("Traceback" not in json.dumps(response), "error leaked traceback")
    return response


def test_statistics() -> None:
    response = require_ok(base_request("compute_statistics", {"values": [1, 2, 3, 4, 5]}, {"ddof": 1}))
    payload = response["artifacts"][0]["payload"]
    require(payload["count"] == 5, "statistics count mismatch")
    require(payload["mean"] == 3.0, "statistics mean mismatch")
    require(payload["stdev"] == 1.581138830084, "statistics stdev mismatch")


def test_regression() -> None:
    response = require_ok(
        base_request(
            "fit_regression",
            {"xValues": [1, 2, 3, 4], "yValues": [3, 5, 7, 9]},
            {"regressionKind": "linear"},
        )
    )
    payload = response["artifacts"][0]["payload"]
    require(payload["slope"] == 2.0, "regression slope mismatch")
    require(payload["intercept"] == 1.0, "regression intercept mismatch")
    require(payload["rSquared"] == 1.0, "regression rSquared mismatch")


def test_distribution() -> None:
    response = require_ok(base_request("bin_distribution", {"values": [0, 1, 2, 3]}, {"binCount": 2}))
    payload = response["artifacts"][0]["payload"]
    require(payload["binCount"] == 2, "bin count mismatch")
    require([item["count"] for item in payload["bins"]] == [2, 2], "bin counts mismatch")


def test_function_sampling() -> None:
    response = require_ok(
        base_request(
            "sample_function",
            {"expression": "sin(x) + x**2", "domain": {"min": 0, "max": 2, "samples": 3}},
        )
    )
    payload = response["artifacts"][0]["payload"]
    require(len(payload["points"]) == 3, "sample count mismatch")
    require(payload["points"][0]["y"] == 0.0, "first sample mismatch")


def test_function_discontinuity_segments() -> None:
    response = require_ok(
        base_request(
            "sample_function",
            {"expression": "1 / x", "domain": {"min": -1, "max": 1, "samples": 3}},
        )
    )
    payload = response["artifacts"][0]["payload"]
    require([len(segment["points"]) for segment in payload["segments"]] == [1, 1], "discontinuity was bridged")


def test_invalid_operation() -> None:
    request = base_request("compute_statistics", {"values": [1]})
    request["operation"] = "custom_python"
    require_error(request, "unsupported_operation")


def test_malicious_expression() -> None:
    request = base_request(
        "sample_function",
        {"expression": "__import__('os').system('echo bad')", "domain": {"min": 0, "max": 1, "samples": 2}},
    )
    require_error(request, "unsafe_expression")


def test_limit_exceeded() -> None:
    request = base_request("compute_statistics", {"values": [1, 2, 3]})
    request["limits"]["maxRows"] = 2
    require_error(request, "limit_exceeded")


def test_invalid_source_label() -> None:
    request = base_request("compute_statistics", {"values": [1, 2, 3]})
    request["sourceEvidenceIDs"] = ["../../private-data"]
    require_error(request, "invalid_source_evidence")


def test_hash_is_canonical() -> None:
    request = base_request("compute_statistics", {"values": [2, 1]})
    first = require_ok(request)["artifacts"][0]["sha256"]
    second = require_ok(request)["artifacts"][0]["sha256"]
    require(first == second, "canonical payload hash is not stable")


def main() -> int:
    tests = [
        test_statistics,
        test_regression,
        test_distribution,
        test_function_sampling,
        test_function_discontinuity_segments,
        test_invalid_operation,
        test_malicious_expression,
        test_limit_exceeded,
        test_invalid_source_label,
        test_hash_is_canonical,
    ]
    for test in tests:
        test()
    print(f"rich_answer_worker_self_test passed: {len(tests)} tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
