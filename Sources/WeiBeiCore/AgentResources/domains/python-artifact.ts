import { spawn } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@earendil-works/pi-ai";
import {
  canonicalJSON,
  safeArtifactIdentifier,
  sha256UTF8,
} from "./canonical-json";
import {
  COMPUTE_ARTIFACT_TOOL,
  CONTEXT_TOOL,
  ComputeArtifactToolDetails,
  LIMITS,
  readCurrentSnapshot,
} from "./agent-context";
import { canonicalRichAnswerEvidenceLabel, richAnswerEvidenceText } from "./rich-answer-validation";


export const PYTHON_ARTIFACT_WORKER_PATH = fileURLToPath(
  new URL("../python/rich_answer_worker.py", import.meta.url),
);

export const PYTHON_ARTIFACT_OPERATIONS = [
  "compute_statistics",
  "fit_regression",
  "bin_distribution",
  "sample_function",
] as const;

export const PYTHON_ARTIFACT_OUTPUT_KINDS = ["json_spec", "numeric_series", "table"] as const;

export type PythonArtifactOperation = typeof PYTHON_ARTIFACT_OPERATIONS[number];

export type PythonArtifactOutputKind = typeof PYTHON_ARTIFACT_OUTPUT_KINDS[number];


// NOTE: 这是隔离 Python 计算工人的独立协议版本，不是 Rich Answer Envelope。
export interface PythonArtifactWorkerSuccess {
  schemaVersion: 1;
  ok: true;
  workerVersion: string;
  requestID: string;
  operation: PythonArtifactOperation;
  artifacts: Array<{
    id: string;
    kind: PythonArtifactOutputKind;
    mimeType: "application/json";
    role: string;
    payload: unknown;
    payloadCanonicalJSON?: string;
    sizeBytes: number;
    sha256: string;
    sourceEvidenceIDs: string[];
    metadata: Record<string, unknown>;
  }>;
  diagnostics: string[];
}


export interface PythonArtifactWorkerFailure {
  schemaVersion?: number;
  ok?: false;
  workerVersion?: string;
  error?: { code?: string; message?: string };
}


export async function runPythonArtifactWorker(
  request: Record<string, unknown>,
  limits: {
    maxInputBytes: number;
    maxOutputBytes: number;
    maxRuntimeMS: number;
  },
): Promise<{
  result: PythonArtifactWorkerSuccess;
  pythonExecutable: string;
  requestSHA256: string;
  outputSHA256: string;
  durationMS: number;
}> {
  const requestJSON = canonicalJSON(request);
  const requestBytes = Buffer.byteLength(requestJSON, "utf8");
  if (requestBytes > limits.maxInputBytes) {
    throw new Error(`受控计算输入超出预算：${requestBytes}/${limits.maxInputBytes} bytes`);
  }

  const pythonExecutable = process.env.WEIBEI_PYTHON_EXECUTABLE?.trim() || "/usr/bin/python3";
  const startedAt = performance.now();
  const outputJSON = await new Promise<string>((resolveOutput, rejectOutput) => {
    const child = spawn(
      pythonExecutable,
      ["-I", "-B", "-S", PYTHON_ARTIFACT_WORKER_PATH],
      {
        cwd: resolve(PYTHON_ARTIFACT_WORKER_PATH, ".."),
        env: {
          PATH: "/usr/bin:/bin",
          PYTHONNOUSERSITE: "1",
          PYTHONDONTWRITEBYTECODE: "1",
          PYTHONHASHSEED: "0",
          LC_ALL: "C.UTF-8",
          LANG: "C.UTF-8",
        },
        shell: false,
        stdio: ["pipe", "pipe", "pipe"],
      },
    );
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let settled = false;
    const finishWithError = (error: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      child.kill("SIGKILL");
      rejectOutput(error);
    };
    const timer = setTimeout(() => {
      finishWithError(new Error(`受控 Python 计算超过 ${limits.maxRuntimeMS}ms`));
    }, limits.maxRuntimeMS);

    child.stdout.on("data", (chunk: Buffer) => {
      stdoutBytes += chunk.length;
      if (stdoutBytes > limits.maxOutputBytes) {
        finishWithError(
          new Error(`受控计算输出超出预算：${stdoutBytes}/${limits.maxOutputBytes} bytes`),
        );
        return;
      }
      stdout.push(chunk);
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderrBytes += chunk.length;
      if (stderrBytes > 8_192) {
        finishWithError(new Error("受控 Python 计算产生了过量诊断输出"));
        return;
      }
      stderr.push(chunk);
    });
    child.on("error", (error) => finishWithError(error));
    child.on("close", (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const output = Buffer.concat(stdout).toString("utf8").trim();
      if (!output) {
        const stderrHash = stderrBytes > 0
          ? sha256UTF8(Buffer.concat(stderr).toString("utf8"))
          : "none";
        rejectOutput(
          new Error(`受控 Python 计算没有返回 JSON（exit=${code ?? "unknown"}, stderrHash=${stderrHash}）`),
        );
        return;
      }
      resolveOutput(output);
    });
    child.stdin.on("error", (error) => finishWithError(error));
    child.stdin.end(`${requestJSON}\n`, "utf8");
  });

  let decoded: PythonArtifactWorkerSuccess | PythonArtifactWorkerFailure;
  try {
    decoded = JSON.parse(outputJSON) as PythonArtifactWorkerSuccess | PythonArtifactWorkerFailure;
  } catch {
    throw new Error("受控 Python 计算返回了无法解析的 JSON");
  }
  if (decoded.ok !== true) {
    const code = decoded.error?.code?.trim() || "worker_error";
    const message = decoded.error?.message?.trim() || "受控 Python 计算失败";
    throw new Error(`${code}: ${message}`);
  }
  if (
    decoded.schemaVersion !== 1 ||
    !decoded.workerVersion ||
    decoded.requestID !== request.requestID ||
    decoded.operation !== request.operation ||
    !Array.isArray(decoded.artifacts) ||
    !Array.isArray(decoded.diagnostics)
  ) {
    throw new Error("受控 Python 计算返回的契约不完整");
  }
  const outputSHA256 = sha256UTF8(outputJSON);
  for (const artifact of decoded.artifacts) {
    if (
      !safeArtifactIdentifier(artifact.id) ||
      !PYTHON_ARTIFACT_OUTPUT_KINDS.includes(artifact.kind) ||
      artifact.mimeType !== "application/json" ||
      !safeArtifactIdentifier(artifact.role) ||
      !Array.isArray(artifact.sourceEvidenceIDs)
    ) {
      throw new Error("受控 Python 计算返回了非法产物元数据");
    }
    if (typeof artifact.payloadCanonicalJSON !== "string") {
      throw new Error(`受控 Python 产物 ${artifact.id} 缺少真实 canonical payload bytes`);
    }
    let canonicalPayload: unknown;
    try {
      canonicalPayload = JSON.parse(artifact.payloadCanonicalJSON);
    } catch {
      throw new Error(`受控 Python 产物 ${artifact.id} 的 canonical payload 无法解析`);
    }
    if (canonicalJSON(canonicalPayload) !== canonicalJSON(artifact.payload)) {
      throw new Error(`受控 Python 产物 ${artifact.id} 的 payload 与 canonical bytes 不一致`);
    }
    const payloadBytes = Buffer.byteLength(artifact.payloadCanonicalJSON, "utf8");
    if (
      artifact.sizeBytes !== payloadBytes ||
      artifact.sha256 !== sha256UTF8(artifact.payloadCanonicalJSON)
    ) {
      throw new Error(`受控 Python 产物 ${artifact.id} 的长度或哈希不匹配`);
    }
    delete artifact.payloadCanonicalJSON;
  }

  return {
    result: decoded,
    pythonExecutable,
    requestSHA256: sha256UTF8(requestJSON),
    outputSHA256,
    durationMS: Math.max(0, Math.round(performance.now() - startedAt)),
  };
}


export const pythonArtifactNumberSeriesSchema = Type.Array(Type.Number(), {
  minItems: 1,
  maxItems: LIMITS.pythonArtifactRows,
});


export const pythonArtifactDataSchema = Type.Object(
  {
    values: Type.Optional(pythonArtifactNumberSeriesSchema),
    xValues: Type.Optional(pythonArtifactNumberSeriesSchema),
    yValues: Type.Optional(pythonArtifactNumberSeriesSchema),
    expression: Type.Optional(Type.String({ minLength: 1, maxLength: 500 })),
    domain: Type.Optional(Type.Object(
      {
        min: Type.Number(),
        max: Type.Number(),
        samples: Type.Integer({ minimum: 16, maximum: 1_000 }),
      },
      { additionalProperties: false },
    )),
  },
  { additionalProperties: false },
);


export const pythonArtifactParametersSchema = Type.Object(
  {
    binCount: Type.Optional(Type.Integer({ minimum: 2, maximum: 100 })),
    ddof: Type.Optional(Type.Integer({ minimum: 0, maximum: 1 })),
    regressionKind: Type.Optional(Type.Literal("linear")),
  },
  { additionalProperties: false },
);

/**
 * Registers the isolated Python artifact tool while keeping request state in the Pi entry.
 */
export function registerPythonArtifactTool(
  pi: ExtensionAPI,
  state: {
    lastReadContextRevision: () => string | undefined;
    searchedCourseItemIDs: ReadonlySet<string>;
  },
) {
  pi.registerTool({
      name: COMPUTE_ARTIFACT_TOOL,
      label: "执行受控专业计算",
      description:
        "用魏碑随 App 打包的固定 Python 工人执行白名单确定性计算。只接受数列、成对数值或受限数学表达式；不执行模型生成代码，不联网，不读取任意文件。结果可作为标准图表、函数或其他注册渲染器的高层数据规格。",
      promptSnippet:
        "需要统计、线性回归、分箱或函数采样时调用受控 Python；保留产物哈希和来源标签，再把结果用于本轮目录返回的专业渲染器",
      parameters: Type.Object(
        {
          contextRevision: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
          requestID: Type.String({ minLength: 1, maxLength: 128 }),
          operation: Type.Union(
            PYTHON_ARTIFACT_OPERATIONS.map((value) => Type.Literal(value)),
          ),
          data: pythonArtifactDataSchema,
          parameters: Type.Optional(pythonArtifactParametersSchema),
          requestedOutput: Type.Object(
            {
              id: Type.String({ minLength: 1, maxLength: 128 }),
              kind: Type.Union(
                PYTHON_ARTIFACT_OUTPUT_KINDS.map((value) => Type.Literal(value)),
              ),
              mimeType: Type.Literal("application/json"),
              role: Type.String({ minLength: 1, maxLength: 128 }),
            },
            { additionalProperties: false },
          ),
          sourceEvidenceIDs: Type.Array(
            Type.String({ minLength: 1, maxLength: 300 }),
            { minItems: 1, maxItems: LIMITS.richAnswerEvidence },
          ),
          reason: Type.String({ minLength: 1, maxLength: 500 }),
        },
        { additionalProperties: false },
      ),
      executionMode: "sequential",
      async execute(_toolCallID, params) {
        const current = await readCurrentSnapshot();
        if (state.lastReadContextRevision() !== current.contextRevision) {
          throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
        }
        if (params.contextRevision !== current.contextRevision) {
          throw new Error("受控计算请求引用了过期的魏碑上下文");
        }
        if (!safeArtifactIdentifier(params.requestID)) {
          throw new Error("受控计算 requestID 只能使用安全的字母、数字、点、下划线或连字符");
        }
        if (
          !safeArtifactIdentifier(params.requestedOutput.id) ||
          !safeArtifactIdentifier(params.requestedOutput.role)
        ) {
          throw new Error("受控计算产物 id/role 只能使用安全标识符");
        }
  
        const availableEvidence = richAnswerEvidenceText(current, state.searchedCourseItemIDs);
        const sourceEvidenceIDs = params.sourceEvidenceIDs.map((sourceLabel) => {
          const canonical = canonicalRichAnswerEvidenceLabel(sourceLabel, availableEvidence.keys());
          if (!canonical) {
            throw new Error(`受控计算引用了本轮不可用的来源标签：${sourceLabel}`);
          }
          return canonical;
        });
        if (new Set(sourceEvidenceIDs).size !== sourceEvidenceIDs.length) {
          throw new Error("受控计算的 sourceEvidenceIDs 不能重复");
        }
  
        const data: Record<string, unknown> = {};
        if (params.data.values !== undefined) data.values = params.data.values;
        if (params.data.xValues !== undefined) data.xValues = params.data.xValues;
        if (params.data.yValues !== undefined) data.yValues = params.data.yValues;
        if (params.data.expression !== undefined) data.expression = params.data.expression.trim();
        if (params.data.domain !== undefined) data.domain = params.data.domain;
        const operation = params.operation as PythonArtifactOperation;
  
        switch (operation) {
          case "compute_statistics": {
            if (!params.data.values?.length) {
              throw new Error("compute_statistics 需要非空 values");
            }
            const ddof = params.parameters?.ddof ?? 0;
            if (ddof >= params.data.values.length) {
              throw new Error("compute_statistics 的 ddof 必须小于样本数量");
            }
            break;
          }
          case "fit_regression":
            if (
              !params.data.xValues ||
              !params.data.yValues ||
              params.data.xValues.length < 2 ||
              params.data.xValues.length !== params.data.yValues.length
            ) {
              throw new Error("fit_regression 需要至少两组成对且等长的 xValues/yValues");
            }
            break;
          case "bin_distribution":
            if (!params.data.values?.length) {
              throw new Error("bin_distribution 需要非空 values");
            }
            break;
          case "sample_function":
            if (
              !params.data.expression?.trim() ||
              !params.data.domain ||
              !(params.data.domain.min < params.data.domain.max)
            ) {
              throw new Error("sample_function 需要受限 expression 和 min < max 的 domain");
            }
            break;
        }
  
        const parameters: Record<string, unknown> = {};
        if (params.parameters?.binCount !== undefined) {
          parameters.binCount = params.parameters.binCount;
        }
        if (params.parameters?.ddof !== undefined) parameters.ddof = params.parameters.ddof;
        if (params.parameters?.regressionKind !== undefined) {
          parameters.regressionKind = params.parameters.regressionKind;
        }
        const limits = {
          maxInputBytes: LIMITS.pythonArtifactInputBytes,
          maxOutputBytes: LIMITS.pythonArtifactOutputBytes,
          maxRows: LIMITS.pythonArtifactRows,
          maxColumns: LIMITS.pythonArtifactColumns,
          maxRuntimeMS: LIMITS.pythonArtifactRuntimeMS,
        };
        const request: Record<string, unknown> = {
          schemaVersion: 1,
          requestID: params.requestID,
          operation,
          data,
          parameters,
          requestedOutput: params.requestedOutput,
          limits,
          sourceEvidenceIDs,
        };
        const execution = await runPythonArtifactWorker(request, limits);
        const { result } = execution;
        if (result.artifacts.length !== 1) {
          throw new Error("受控 Python 工人必须且只能返回一个请求产物");
        }
        const artifact = result.artifacts[0];
        if (
          artifact.id !== params.requestedOutput.id ||
          artifact.kind !== params.requestedOutput.kind ||
          artifact.mimeType !== params.requestedOutput.mimeType ||
          artifact.role !== params.requestedOutput.role
        ) {
          throw new Error("受控 Python 工人返回的产物与 requestedOutput 不一致");
        }
        if (
          artifact.sourceEvidenceIDs.length !== sourceEvidenceIDs.length ||
          artifact.sourceEvidenceIDs.some((sourceID) => !sourceEvidenceIDs.includes(sourceID))
        ) {
          throw new Error("受控 Python 工人没有保留完整来源绑定");
        }
        if (
          result.diagnostics.some(
            (diagnostic) => typeof diagnostic !== "string" || diagnostic.length > 500,
          )
        ) {
          throw new Error("受控 Python 工人返回了非法诊断信息");
        }
  
        const details: ComputeArtifactToolDetails = {
          kind: "compute_artifact",
          schemaVersion: 1,
          contextRevision: current.contextRevision,
          requestID: result.requestID,
          operation: result.operation,
          workerVersion: result.workerVersion,
          pythonExecutable: execution.pythonExecutable,
          requestSHA256: execution.requestSHA256,
          outputSHA256: execution.outputSHA256,
          durationMS: execution.durationMS,
          artifacts: result.artifacts.map((produced) => ({
            id: produced.id,
            kind: produced.kind,
            mimeType: produced.mimeType,
            role: produced.role,
            sizeBytes: produced.sizeBytes,
            sha256: produced.sha256,
            sourceEvidenceIDs: produced.sourceEvidenceIDs,
          })),
          diagnostics: result.diagnostics,
        };
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  requestID: result.requestID,
                  operation: result.operation,
                  workerVersion: result.workerVersion,
                  artifacts: result.artifacts,
                  diagnostics: result.diagnostics,
                  nextUse: [
                    "只把产物 payload 中与当前学习目标有关的高层数据放进本轮目录返回的 renderPlan.spec；不要复制成 raw 图表配置或代码。",
                    "把产物 id/kind/mimeType/sizeBytes/sha256 记录到 renderPlan.artifacts，并用 evidenceLedger 与 sourceBindings 继续绑定同一真实来源。",
                    "若计算结果与材料、单位或专业判断冲突，先解释冲突并重新核对，不用图形掩盖。",
                  ],
                },
                null,
                2,
              ),
            },
          ],
          details,
        };
      },
    });
}
