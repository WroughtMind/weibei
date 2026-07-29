import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { afterEach, describe, expect, it } from "vitest";

import weibeiExtension from "../../Sources/WeiBeiCore/AgentResources/extension.js";

interface RegisteredTool {
  name: string;
  execute(toolCallID: string, params: Record<string, unknown>): Promise<unknown>;
}

type EventHandler = (event: Record<string, unknown>) => unknown;

interface ExtensionHarness {
  contextFile: string;
  handlers: Map<string, EventHandler>;
  tools: Map<string, RegisteredTool>;
  writeContext(context: Record<string, unknown>): Promise<void>;
}

const temporaryDirectories: string[] = [];

/**
 * 构造覆盖 Extension 行为测试所需的最小合法上下文快照。
 *
 * @param overrides - 需要替换的顶层上下文字段
 * @returns 可写入 Agent 上下文文件的版本 2 快照
 */
function makeContext(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schemaVersion: 2,
    requestID: "request-1",
    contextRevision: "revision-1",
    answerFormPolicy: "automatic",
    purpose: "answer",
    workflow: "learning",
    language: "zh-CN",
    question: "解释当前材料",
    material: {
      title: "材料一",
      text: "魏碑材料中的真实证据。",
      isTruncated: false,
    },
    note: {
      title: "笔记一",
      text: "用户笔记中的真实证据。",
      isTruncated: false,
    },
    selection: null,
    recentMessages: [
      {
        role: "user",
        text: "我还不理解这个概念",
      },
    ],
    course: {
      title: "课程一",
      catalog: [],
      items: [],
      relations: [],
      isTruncated: false,
    },
    learning: {
      memoryRevision: 3,
      memories: [
        {
          id: "memory-1",
          kind: "confusion",
          text: "尚未理解概念",
          evidence: "[用户：本轮]我还不理解这个概念",
          origin: "userStatement",
          status: "active",
          createdAt: 1,
          updatedAt: 1,
        },
      ],
      lastLocation: null,
      session: null,
    },
    ...overrides,
  };
}

/**
 * 注册 Extension 到 fake API，并将工具及事件处理器暴露给行为测试。
 *
 * @param context - 初始上下文快照
 * @returns 隔离的 Extension 测试驱动
 */
async function createHarness(context = makeContext()): Promise<ExtensionHarness> {
  const directory = await mkdtemp(join(tmpdir(), "weibei-extension-test-"));
  temporaryDirectories.push(directory);
  const contextFile = join(directory, "context.json");
  await writeFile(contextFile, JSON.stringify(context));
  process.env.WEIBEI_AGENT_CONTEXT_FILE = contextFile;

  const tools = new Map<string, RegisteredTool>();
  const handlers = new Map<string, EventHandler>();
  const fakeAPI = {
    registerTool(tool: RegisteredTool) {
      tools.set(tool.name, tool);
    },
    on(event: string, handler: EventHandler) {
      handlers.set(event, handler);
    },
  };
  weibeiExtension(fakeAPI as unknown as ExtensionAPI);

  return {
    contextFile,
    handlers,
    tools,
    async writeContext(nextContext) {
      await writeFile(contextFile, JSON.stringify(nextContext));
    },
  };
}

/**
 * 调用已捕获的 Extension 事件处理器。
 *
 * @param harness - Extension 测试驱动
 * @param event - 事件名称
 * @param payload - 事件参数
 * @returns 处理器返回值
 */
async function dispatch(
  harness: ExtensionHarness,
  event: string,
  payload: Record<string, unknown>,
): Promise<unknown> {
  const handler = harness.handlers.get(event);
  if (!handler) throw new Error(`缺少事件处理器：${event}`);
  return await handler(payload);
}

/**
 * 执行指定的已注册工具。
 *
 * @param harness - Extension 测试驱动
 * @param name - 工具名称
 * @param params - 工具参数
 * @returns 工具执行结果
 */
async function executeTool(
  harness: ExtensionHarness,
  name: string,
  params: Record<string, unknown> = {},
): Promise<unknown> {
  const tool = harness.tools.get(name);
  if (!tool) throw new Error(`缺少工具：${name}`);
  return await tool.execute("tool-call-1", params);
}

afterEach(async () => {
  delete process.env.WEIBEI_AGENT_CONTEXT_FILE;
  await Promise.all(temporaryDirectories.splice(0).map((directory) =>
    rm(directory, { recursive: true, force: true })
  ));
});

describe.sequential("WeiBei Pi Agent Extension", () => {
  it("registers only the supported tool contract", async () => {
    const harness = await createHarness();

    expect([...harness.tools.keys()]).toEqual([
      "weibei_context",
      "weibei_visual_asset",
      "weibei_course_map",
      "weibei_course_search",
      "weibei_compute_artifact",
      "weibei_ui_catalog",
      "weibei_rich_answer",
      "weibei_learning_memory",
      "weibei_learning_update",
      "weibei_note_proposal",
    ]);
    expect([...harness.handlers.keys()]).toEqual([
      "before_agent_start",
      "tool_call",
      "tool_result",
      "context",
    ]);
  });

  it("requires context first and rejects tools outside the allowlist", async () => {
    const harness = await createHarness();
    await dispatch(harness, "before_agent_start", { systemPrompt: "system" });

    await expect(dispatch(harness, "tool_call", {
      toolName: "weibei_course_map",
      input: {},
    })).resolves.toMatchObject({
      block: true,
      reason: expect.stringContaining("必须先调用 weibei_context"),
    });
    await expect(dispatch(harness, "tool_call", {
      toolName: "bash",
      input: { command: "pwd" },
    })).resolves.toMatchObject({
      block: true,
      reason: expect.stringContaining("只允许"),
    });
  });

  it("allows read only for bundled Rich Answer skills", async () => {
    const harness = await createHarness();
    await dispatch(harness, "before_agent_start", { systemPrompt: "system" });
    await executeTool(harness, "weibei_context");

    await expect(dispatch(harness, "tool_call", {
      toolName: "read",
      input: { path: "/etc/hosts" },
    })).resolves.toMatchObject({
      block: true,
      reason: expect.stringContaining("不能读取其它文件"),
    });
    await expect(dispatch(harness, "tool_call", {
      toolName: "read",
      input: { path: join(tmpdir(), "..", "etc", "hosts") },
    })).resolves.toMatchObject({
      block: true,
    });
  });

  it("enforces context revision and evidence on note proposals", async () => {
    const harness = await createHarness();
    await executeTool(harness, "weibei_context");

    await expect(executeTool(harness, "weibei_note_proposal", {
      markdown: "建议正文",
      evidence: ["[材料：材料一]魏碑材料中的真实证据。"],
      contextRevision: "stale-revision",
    })).rejects.toThrow("contextRevision 不匹配");

    await expect(executeTool(harness, "weibei_note_proposal", {
      markdown: "建议正文",
      evidence: ["无来源证据"],
      contextRevision: "revision-1",
    })).rejects.toThrow("真实来源标签");

    await expect(executeTool(harness, "weibei_note_proposal", {
      markdown: "建议正文",
      evidence: ["[材料：材料一]魏碑材料中的真实证据。"],
      contextRevision: "revision-1",
    })).resolves.toMatchObject({
      details: {
        kind: "note_proposal",
        contextRevision: "revision-1",
      },
    });
  });

  it("rejects note proposals after the context file changes", async () => {
    const harness = await createHarness();
    await executeTool(harness, "weibei_context");
    await harness.writeContext(makeContext({ contextRevision: "revision-2" }));

    await expect(executeTool(harness, "weibei_note_proposal", {
      markdown: "建议正文",
      evidence: ["[材料：材料一]魏碑材料中的真实证据。"],
      contextRevision: "revision-1",
    })).rejects.toThrow("上下文已变化");
  });

  it("requires a fresh memory read and matching memory revision for updates", async () => {
    const harness = await createHarness();
    await executeTool(harness, "weibei_context");

    const update = {
      contextRevision: "revision-1",
      memoryRevision: 3,
      suggestedNext: ["复习概念"],
      entries: [],
    };
    await expect(executeTool(harness, "weibei_learning_update", update))
      .rejects.toThrow("重新调用 weibei_context 和 weibei_learning_memory");

    await executeTool(harness, "weibei_learning_memory");
    await expect(executeTool(harness, "weibei_learning_update", {
      ...update,
      memoryRevision: 2,
    })).rejects.toThrow("修订号不匹配");

    await expect(executeTool(harness, "weibei_learning_update", update)).resolves.toMatchObject({
      details: {
        kind: "learning_update",
        memoryRevision: 3,
      },
    });
  });

  it("rejects Rich Answer submissions without current context or readable evidence", async () => {
    const noEvidenceContext = makeContext({
      material: null,
      note: {
        title: "空笔记",
        text: "",
        isTruncated: false,
      },
    });
    const harness = await createHarness(noEvidenceContext);

    await expect(executeTool(harness, "weibei_rich_answer", {
      contextRevision: "revision-1",
    })).rejects.toThrow("context_required");

    await executeTool(harness, "weibei_context");
    await executeTool(harness, "weibei_ui_catalog", {
      learningAction: "explain",
      knowledgeShapes: ["comparison"],
      knowledgeNatures: ["conceptual"],
      knowledgeObjects: ["概念"],
      knowledgeRelations: [],
      knowledgeProcesses: [],
      interactions: ["inspect"],
      sourceMedium: "text",
      surface: "inline",
      reason: "帮助理解",
    });
    await expect(executeTool(harness, "weibei_rich_answer", {
      schemaVersion: 2,
      contextRevision: "revision-1",
      narrative: "没有可用来源。",
      expressionPlan: {},
      scenes: [],
      evidenceLedger: [
        {
          id: "evidence-1",
          sourceLabel: "[材料：不存在]",
          excerpt: "不存在",
        },
      ],
      fallback: "普通文本",
    })).rejects.toThrow("source_not_available");
  });

  it("blocks Rich Answer tools when the current policy is text only", async () => {
    const harness = await createHarness(makeContext({ answerFormPolicy: "textOnly" }));
    await dispatch(harness, "before_agent_start", { systemPrompt: "system" });
    await executeTool(harness, "weibei_context");

    await expect(dispatch(harness, "tool_call", {
      toolName: "weibei_rich_answer",
      input: {},
    })).resolves.toMatchObject({
      block: true,
      reason: expect.stringContaining("textOnly"),
    });
  });
});
