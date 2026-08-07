#!/usr/bin/env python3
"""WeiBei controlled rich-answer Python worker.

Reads one JSON request from stdin and writes one JSON response to stdout.
Only four fixed operations are supported. User code, network access, and
arbitrary file access are intentionally absent.
"""

from __future__ import annotations

import ast
import hashlib
import json
import math
import sys
from dataclasses import dataclass
from typing import Any


WORKER_VERSION = "1.0.0"
SCHEMA_VERSION = 1
HARD_MAX_INPUT_BYTES = 256_000
HARD_MAX_OUTPUT_BYTES = 512_000
HARD_MAX_ROWS = 2_000
HARD_MAX_COLUMNS = 80
HARD_MAX_POINTS = 2_000
HARD_MAX_EXPRESSION_NODES = 96
HARD_MAX_EXPRESSION_DEPTH = 24
HARD_MAX_MAGNITUDE = 1.0e12
SAFE_ID_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
SAFE_SOURCE_PREFIXES = ("[材料：", "[笔记：", "[选区：")

ALLOWED_OPERATIONS = {
    "compute_statistics",
    "fit_regression",
    "bin_distribution",
    "sample_function",
}
ALLOWED_OUTPUT_KINDS = {"json_spec", "numeric_series", "table"}
ALLOWED_REGRESSION_KINDS = {"linear"}


class WorkerError(Exception):
    def __init__(self, code: str, message: str, field: str | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.field = field


@dataclass(frozen=True)
class Limits:
    max_input_bytes: int = HARD_MAX_INPUT_BYTES
    max_output_bytes: int = HARD_MAX_OUTPUT_BYTES
    max_rows: int = HARD_MAX_ROWS
    max_columns: int = HARD_MAX_COLUMNS
    max_runtime_ms: int = 3_000


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def json_size(value: Any) -> int:
    return len(canonical_json(value).encode("utf-8"))


def sha256_payload(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def is_safe_id(value: str) -> bool:
    return 1 <= len(value) <= 128 and all(char in SAFE_ID_CHARS for char in value)


def is_safe_source_evidence(value: str) -> bool:
    return (
        4 <= len(value) <= 300
        and value.startswith(SAFE_SOURCE_PREFIXES)
        and value.endswith("]")
        and all(ord(char) >= 32 and char not in {"\x7f", "\x00"} for char in value)
    )


def as_object(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise WorkerError("invalid_object", f"{field} must be an object", field)
    return value


def as_string(value: Any, field: str) -> str:
    if not isinstance(value, str):
        raise WorkerError("invalid_string", f"{field} must be a string", field)
    return value


def as_optional_string(value: Any, field: str, default: str) -> str:
    if value is None:
        return default
    return as_string(value, field)


def as_number(value: Any, field: str) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise WorkerError("invalid_number", f"{field} must be a finite number", field)
    number = float(value)
    if not math.isfinite(number) or abs(number) > HARD_MAX_MAGNITUDE:
        raise WorkerError("invalid_number", f"{field} must be finite and within magnitude guard", field)
    return number


def as_optional_number(value: Any, field: str, default: float) -> float:
    if value is None:
        return default
    return as_number(value, field)


def as_int(value: Any, field: str, default: int, minimum: int, maximum: int) -> int:
    if value is None:
        return default
    if not isinstance(value, int) or isinstance(value, bool):
        raise WorkerError("invalid_integer", f"{field} must be an integer", field)
    if value < minimum or value > maximum:
        raise WorkerError("limit_exceeded", f"{field} must be between {minimum} and {maximum}", field)
    return value


def safe_number(value: float | None) -> float | None:
    if value is None or not math.isfinite(value) or abs(value) > HARD_MAX_MAGNITUDE:
        return None
    rounded = round(value, 12)
    return 0.0 if rounded == -0.0 else rounded


def percentile(sorted_values: list[float], ratio: float) -> float:
    position = (len(sorted_values) - 1) * ratio
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return sorted_values[lower]
    weight = position - lower
    return sorted_values[lower] * (1 - weight) + sorted_values[upper] * weight


def mean_value(values: list[float]) -> float:
    return sum(values) / len(values)


def median_value(sorted_values: list[float]) -> float:
    midpoint = len(sorted_values) // 2
    if len(sorted_values) % 2 == 1:
        return sorted_values[midpoint]
    return (sorted_values[midpoint - 1] + sorted_values[midpoint]) / 2


def parse_limits(request: dict[str, Any]) -> Limits:
    raw_limits = as_object(request.get("limits", {}), "limits")
    return Limits(
        max_input_bytes=min(
            as_int(raw_limits.get("maxInputBytes"), "limits.maxInputBytes", HARD_MAX_INPUT_BYTES, 1, HARD_MAX_INPUT_BYTES),
            HARD_MAX_INPUT_BYTES,
        ),
        max_output_bytes=min(
            as_int(raw_limits.get("maxOutputBytes"), "limits.maxOutputBytes", HARD_MAX_OUTPUT_BYTES, 1_024, HARD_MAX_OUTPUT_BYTES),
            HARD_MAX_OUTPUT_BYTES,
        ),
        max_rows=min(as_int(raw_limits.get("maxRows"), "limits.maxRows", HARD_MAX_ROWS, 1, HARD_MAX_ROWS), HARD_MAX_ROWS),
        max_columns=min(as_int(raw_limits.get("maxColumns"), "limits.maxColumns", HARD_MAX_COLUMNS, 1, HARD_MAX_COLUMNS), HARD_MAX_COLUMNS),
        max_runtime_ms=min(as_int(raw_limits.get("maxRuntimeMS"), "limits.maxRuntimeMS", 3_000, 1, 3_000), 3_000),
    )


def number_array(value: Any, field: str, limit: int) -> list[float]:
    if not isinstance(value, list):
        raise WorkerError("invalid_number_array", f"{field} must be a number array", field)
    if len(value) > limit:
        raise WorkerError("limit_exceeded", f"{field} exceeds row/point limit", field)
    result = [as_number(item, f"{field}[{index}]") for index, item in enumerate(value)]
    if not result:
        raise WorkerError("empty_array", f"{field} must not be empty", field)
    return result


def parse_request(raw: Any, input_size: int) -> tuple[dict[str, Any], Limits]:
    request = as_object(raw, "request")
    if request.get("schemaVersion") != SCHEMA_VERSION:
        raise WorkerError("unsupported_schema", "schemaVersion must be 1", "schemaVersion")
    request_id = as_string(request.get("requestID"), "requestID")
    if not is_safe_id(request_id):
        raise WorkerError("invalid_identifier", "requestID must be a safe identifier", "requestID")
    operation = as_string(request.get("operation"), "operation")
    if operation not in ALLOWED_OPERATIONS:
        raise WorkerError("unsupported_operation", f"unsupported operation: {operation}", "operation")
    as_object(request.get("data"), "data")
    as_object(request.get("parameters", {}), "parameters")
    requested_output = as_object(request.get("requestedOutput"), "requestedOutput")
    output_id = as_string(requested_output.get("id"), "requestedOutput.id")
    if not is_safe_id(output_id):
        raise WorkerError("invalid_identifier", "requestedOutput.id must be a safe identifier", "requestedOutput.id")
    output_kind = as_string(requested_output.get("kind"), "requestedOutput.kind")
    if output_kind not in ALLOWED_OUTPUT_KINDS:
        raise WorkerError("unsupported_output_kind", f"unsupported output kind: {output_kind}", "requestedOutput.kind")
    if requested_output.get("mimeType") != "application/json":
        raise WorkerError("unsupported_mime_type", "requestedOutput.mimeType must be application/json", "requestedOutput.mimeType")
    as_string(requested_output.get("role"), "requestedOutput.role")
    source_evidence_ids = request.get("sourceEvidenceIDs")
    if (
        not isinstance(source_evidence_ids, list)
        or len(source_evidence_ids) > 12
        or len(set(source_evidence_ids)) != len(source_evidence_ids)
        or not all(isinstance(item, str) and is_safe_source_evidence(item) for item in source_evidence_ids)
    ):
        raise WorkerError(
            "invalid_source_evidence",
            "sourceEvidenceIDs must be empty or contain unique current WeiBei material, note, or selection labels",
            "sourceEvidenceIDs",
        )
    limits = parse_limits(request)
    if input_size > limits.max_input_bytes:
        raise WorkerError("limit_exceeded", "stdin exceeds maxInputBytes", "limits.maxInputBytes")
    return request, limits


def make_artifact(request: dict[str, Any], payload: dict[str, Any], metadata: dict[str, Any] | None = None) -> dict[str, Any]:
    requested_output = as_object(request["requestedOutput"], "requestedOutput")
    payload_json = canonical_json(payload)
    size_bytes = len(payload_json.encode("utf-8"))
    return {
        "id": requested_output["id"],
        "kind": requested_output["kind"],
        "mimeType": requested_output["mimeType"],
        "role": requested_output["role"],
        "payload": payload,
        "payloadCanonicalJSON": payload_json,
        "sizeBytes": size_bytes,
        "sha256": hashlib.sha256(payload_json.encode("utf-8")).hexdigest(),
        "sourceEvidenceIDs": request["sourceEvidenceIDs"],
        "metadata": metadata or {},
    }


def compute_statistics(request: dict[str, Any], limits: Limits) -> list[dict[str, Any]]:
    data = as_object(request["data"], "data")
    parameters = as_object(request.get("parameters", {}), "parameters")
    values = number_array(data.get("values"), "data.values", limits.max_rows)
    ddof = as_int(parameters.get("ddof"), "parameters.ddof", 0, 0, 1)
    sorted_values = sorted(values)
    count = len(values)
    average = mean_value(values)
    median = median_value(sorted_values)
    variance = sum((value - average) ** 2 for value in values) / (count - ddof) if count > ddof else 0.0
    stdev = math.sqrt(variance)
    payload = {
        "type": "statisticsSummary",
        "count": count,
        "ddof": ddof,
        "min": safe_number(min(values)),
        "q1": safe_number(percentile(sorted_values, 0.25)),
        "median": safe_number(median),
        "q3": safe_number(percentile(sorted_values, 0.75)),
        "max": safe_number(max(values)),
        "sum": safe_number(sum(values)),
        "mean": safe_number(average),
        "variance": safe_number(variance),
        "stdev": safe_number(stdev),
        "chartData": [
            {"metric": "min", "value": safe_number(min(values))},
            {"metric": "q1", "value": safe_number(percentile(sorted_values, 0.25))},
            {"metric": "median", "value": safe_number(median)},
            {"metric": "q3", "value": safe_number(percentile(sorted_values, 0.75))},
            {"metric": "max", "value": safe_number(max(values))},
        ],
    }
    return [make_artifact(request, payload, {"operation": "compute_statistics"})]


def fit_regression(request: dict[str, Any], limits: Limits) -> list[dict[str, Any]]:
    data = as_object(request["data"], "data")
    parameters = as_object(request.get("parameters", {}), "parameters")
    regression_kind = as_optional_string(parameters.get("regressionKind"), "parameters.regressionKind", "linear")
    if regression_kind not in ALLOWED_REGRESSION_KINDS:
        raise WorkerError("unsupported_regression_kind", "only linear regression is supported", "parameters.regressionKind")
    x_values = number_array(data.get("xValues"), "data.xValues", limits.max_rows)
    y_values = number_array(data.get("yValues"), "data.yValues", limits.max_rows)
    if len(x_values) != len(y_values):
        raise WorkerError("shape_mismatch", "xValues and yValues must have the same length", "data.yValues")
    if len(x_values) < 2:
        raise WorkerError("insufficient_data", "linear regression needs at least two points", "data.xValues")
    mean_x = mean_value(x_values)
    mean_y = mean_value(y_values)
    x_sum_squares = sum((value - mean_x) ** 2 for value in x_values)
    if x_sum_squares == 0:
        raise WorkerError("singular_regression", "xValues must not all be equal", "data.xValues")
    slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(x_values, y_values)) / x_sum_squares
    intercept = mean_y - slope * mean_x
    fitted = [intercept + slope * x for x in x_values]
    residuals = [y - fit for y, fit in zip(y_values, fitted)]
    total_sum_squares = sum((y - mean_y) ** 2 for y in y_values)
    residual_sum_squares = sum(residual ** 2 for residual in residuals)
    r_squared = 1.0 if total_sum_squares == 0 else 1.0 - residual_sum_squares / total_sum_squares
    payload = {
        "type": "linearRegression",
        "model": "y = slope * x + intercept",
        "slope": safe_number(slope),
        "intercept": safe_number(intercept),
        "rSquared": safe_number(r_squared),
        "count": len(x_values),
        "points": [
            {
                "x": safe_number(x),
                "y": safe_number(y),
                "fit": safe_number(fit),
                "residual": safe_number(residual),
            }
            for x, y, fit, residual in zip(x_values, y_values, fitted, residuals)
        ],
        "chart": {"type": "scatterWithRegression", "xField": "x", "yField": "y", "fitField": "fit"},
    }
    return [make_artifact(request, payload, {"operation": "fit_regression", "regressionKind": regression_kind})]


def bin_distribution(request: dict[str, Any], limits: Limits) -> list[dict[str, Any]]:
    data = as_object(request["data"], "data")
    parameters = as_object(request.get("parameters", {}), "parameters")
    values = number_array(data.get("values"), "data.values", limits.max_rows)
    default_bins = min(12, max(1, int(math.sqrt(len(values)))))
    bin_count = as_int(parameters.get("binCount"), "parameters.binCount", default_bins, 1, min(100, limits.max_rows))
    lower = min(values)
    upper = max(values)
    if lower == upper:
        upper = lower + 1.0
    width = (upper - lower) / bin_count
    counts = [0 for _ in range(bin_count)]
    for value in values:
        index = min(bin_count - 1, int((value - lower) / width))
        counts[index] += 1
    bins = []
    for index, count in enumerate(counts):
        start = lower + index * width
        end = start + width
        bins.append(
            {
                "bin": index + 1,
                "start": safe_number(start),
                "end": safe_number(end),
                "midpoint": safe_number((start + end) / 2),
                "count": count,
                "density": safe_number(count / (len(values) * width)),
            }
        )
    payload = {
        "type": "distributionBins",
        "count": len(values),
        "binCount": bin_count,
        "bins": bins,
        "chart": {"type": "histogram", "xField": "midpoint", "yField": "count"},
    }
    return [make_artifact(request, payload, {"operation": "bin_distribution"})]


ALLOWED_FUNCTIONS = {
    "abs": abs,
    "acos": math.acos,
    "asin": math.asin,
    "atan": math.atan,
    "ceil": math.ceil,
    "cos": math.cos,
    "exp": math.exp,
    "floor": math.floor,
    "ln": math.log,
    "log": math.log,
    "log10": math.log10,
    "max": max,
    "min": min,
    "pow": pow,
    "sin": math.sin,
    "sqrt": math.sqrt,
    "tan": math.tan,
}

ALLOWED_AST_NODES = (
    ast.Expression,
    ast.BinOp,
    ast.UnaryOp,
    ast.Constant,
    ast.Name,
    ast.Call,
    ast.Load,
    ast.Add,
    ast.Sub,
    ast.Mult,
    ast.Div,
    ast.Pow,
    ast.USub,
    ast.UAdd,
)


class SafeExpression:
    def __init__(self, expression: str) -> None:
        self.node_count = 0
        try:
            self.root = ast.parse(expression, mode="eval")
        except SyntaxError as error:
            raise WorkerError("invalid_expression", "expression is not valid arithmetic syntax", "data.expression") from error
        self._validate(self.root, 0)

    def _validate(self, node: ast.AST, depth: int) -> None:
        self.node_count += 1
        if self.node_count > HARD_MAX_EXPRESSION_NODES:
            raise WorkerError("expression_too_large", "expression has too many nodes", "data.expression")
        if depth > HARD_MAX_EXPRESSION_DEPTH:
            raise WorkerError("expression_too_deep", "expression is too deeply nested", "data.expression")
        if not isinstance(node, ALLOWED_AST_NODES):
            raise WorkerError("unsafe_expression", f"unsupported expression node: {type(node).__name__}", "data.expression")
        if isinstance(node, ast.Constant):
            as_number(node.value, "data.expression.constant")
        if isinstance(node, ast.Name):
            if node.id not in {"x", "pi", "e"}:
                raise WorkerError("unsafe_expression", f"unknown identifier: {node.id}", "data.expression")
        if isinstance(node, ast.Call):
            if not isinstance(node.func, ast.Name) or node.func.id not in ALLOWED_FUNCTIONS:
                raise WorkerError("unsafe_expression", "only allowlisted math calls are supported", "data.expression")
            if node.keywords:
                raise WorkerError("unsafe_expression", "keyword arguments are not supported", "data.expression")
            for argument in node.args:
                self._validate(argument, depth + 1)
            return
        for child in ast.iter_child_nodes(node):
            self._validate(child, depth + 1)

    def evaluate(self, x_value: float) -> float:
        return as_number(self._compute_node(self.root, x_value), "data.expression.result")

    def _compute_node(self, node: ast.AST, x_value: float) -> float:
        if isinstance(node, ast.Expression):
            return self._compute_node(node.body, x_value)
        if isinstance(node, ast.Constant):
            return float(node.value)
        if isinstance(node, ast.Name):
            if node.id == "x":
                return x_value
            if node.id == "pi":
                return math.pi
            if node.id == "e":
                return math.e
            raise WorkerError("unsafe_expression", f"unexpected identifier: {node.id}", "data.expression")
        if isinstance(node, ast.UnaryOp):
            operand = self._compute_node(node.operand, x_value)
            if isinstance(node.op, ast.USub):
                return -operand
            if isinstance(node.op, ast.UAdd):
                return operand
        if isinstance(node, ast.BinOp):
            left = self._compute_node(node.left, x_value)
            right = self._compute_node(node.right, x_value)
            if isinstance(node.op, ast.Add):
                return left + right
            if isinstance(node.op, ast.Sub):
                return left - right
            if isinstance(node.op, ast.Mult):
                return left * right
            if isinstance(node.op, ast.Div):
                if right == 0:
                    raise WorkerError("domain_error", "division by zero", "data.expression")
                return left / right
            if isinstance(node.op, ast.Pow):
                return math.pow(left, right)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            return float(
                ALLOWED_FUNCTIONS[node.func.id](
                    *[self._compute_node(argument, x_value) for argument in node.args]
                )
            )
        raise WorkerError("unsafe_expression", "unsupported arithmetic form", "data.expression")


def sample_function(request: dict[str, Any], limits: Limits) -> list[dict[str, Any]]:
    data = as_object(request["data"], "data")
    expression = as_string(data.get("expression"), "data.expression")
    domain = as_object(data.get("domain"), "data.domain")
    lower = as_number(domain.get("min"), "data.domain.min")
    upper = as_number(domain.get("max"), "data.domain.max")
    if upper <= lower:
        raise WorkerError("invalid_domain", "domain.max must be greater than domain.min", "data.domain.max")
    samples = as_int(domain.get("samples"), "data.domain.samples", 121, 2, min(HARD_MAX_POINTS, limits.max_rows))
    safe_expression = SafeExpression(expression)
    step = (upper - lower) / (samples - 1)
    points = []
    for index in range(samples):
        x_value = lower + step * index
        try:
            y_value = safe_expression.evaluate(x_value)
            points.append({"x": safe_number(x_value), "y": safe_number(y_value), "defined": True})
        except (ValueError, OverflowError, WorkerError):
            points.append({"x": safe_number(x_value), "y": None, "defined": False})
    segments: list[dict[str, Any]] = []
    current_segment: list[dict[str, Any]] = []
    for point in points:
        if point["defined"]:
            current_segment.append(point)
        elif current_segment:
            segments.append({"points": current_segment})
            current_segment = []
    if current_segment:
        segments.append({"points": current_segment})
    payload = {
        "type": "functionSamples",
        "expression": expression,
        "domain": {"min": safe_number(lower), "max": safe_number(upper), "samples": samples},
        "points": points,
        "segments": segments,
        "chart": {"type": "line", "xField": "x", "yField": "y"},
    }
    return [make_artifact(request, payload, {"operation": "sample_function", "variable": "x"})]


OPERATIONS = {
    "compute_statistics": compute_statistics,
    "fit_regression": fit_regression,
    "bin_distribution": bin_distribution,
    "sample_function": sample_function,
}


def success_response(request: dict[str, Any], artifacts: list[dict[str, Any]], limits: Limits) -> dict[str, Any]:
    response = {
        "schemaVersion": SCHEMA_VERSION,
        "ok": True,
        "workerVersion": WORKER_VERSION,
        "requestID": request["requestID"],
        "operation": request["operation"],
        "artifacts": artifacts,
        "diagnostics": [
            "network=disabled",
            "filesystem=disabled",
            "userCode=disabled",
            f"maxRows={limits.max_rows}",
            f"maxOutputBytes={limits.max_output_bytes}",
        ],
    }
    if json_size(response) > limits.max_output_bytes:
        raise WorkerError("limit_exceeded", "response exceeds maxOutputBytes", "limits.maxOutputBytes")
    return response


def error_response(error: WorkerError) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "ok": False,
        "workerVersion": WORKER_VERSION,
        "error": {"code": error.code, "message": error.message},
    }
    if error.field is not None:
        payload["error"]["field"] = error.field
    return payload


def run(raw_request: Any, input_size: int) -> dict[str, Any]:
    request, limits = parse_request(raw_request, input_size)
    artifacts = OPERATIONS[request["operation"]](request, limits)
    return success_response(request, artifacts, limits)


def main() -> int:
    try:
        raw_bytes = sys.stdin.buffer.read(HARD_MAX_INPUT_BYTES + 1)
        if len(raw_bytes) > HARD_MAX_INPUT_BYTES:
            raise WorkerError("limit_exceeded", "stdin exceeds hard maxInputBytes", "stdin")
        try:
            raw_request = json.loads(raw_bytes.decode("utf-8"))
        except UnicodeDecodeError as error:
            raise WorkerError("invalid_json", "stdin must be UTF-8 JSON", "stdin") from error
        except json.JSONDecodeError as error:
            raise WorkerError("invalid_json", f"stdin is not valid JSON: {error.msg}", "stdin") from error
        response = run(raw_request, len(raw_bytes))
        sys.stdout.write(canonical_json(response) + "\n")
        return 0
    except WorkerError as error:
        sys.stdout.write(canonical_json(error_response(error)) + "\n")
        return 1
    except Exception:
        sys.stdout.write(canonical_json(error_response(WorkerError("internal_error", "worker failed internally"))) + "\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
