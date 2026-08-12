import {
  lstat,
  mkdtemp,
  mkdir,
  readFile,
  realpath,
  rename,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { build } from "esbuild";

const repositoryRoot = process.cwd();
const resourcesRoot = resolve(repositoryRoot, "Sources/WeiBeiCore/AgentResources");
const temporaryRoot = await mkdtemp(join(tmpdir(), "weibei-project-tools-"));

function requireValue(value, message) {
  if (value === undefined || value === null || value === false) {
    throw new Error(message);
  }
  return value;
}

async function identity(path) {
  const stats = await lstat(path, { bigint: true });
  return {
    volumeID: String(stats.dev),
    fileID: String(stats.ino),
    birthTimeSeconds: String(stats.birthtimeNs / 1_000_000_000n),
    birthTimeNanoseconds: String(stats.birthtimeNs % 1_000_000_000n),
  };
}

try {
  await symlink(join(resourcesRoot, "skills"), join(temporaryRoot, "skills"));
  const outputURL = join(temporaryRoot, "extension.mjs");
  await build({
    entryPoints: [join(resourcesRoot, "extension.ts")],
    bundle: true,
    format: "esm",
    platform: "node",
    target: "node22",
    outfile: outputURL,
    plugins: [{
      name: "pi-ai-self-check-stub",
      setup(builder) {
        builder.onResolve({ filter: /^@earendil-works\/pi-ai(?:\/compat)?$/ }, (args) => ({
          path: args.path.endsWith("/compat") ? "pi-ai-compat" : "pi-ai",
          namespace: "self-check",
        }));
        builder.onLoad({ filter: /.*/, namespace: "self-check" }, (args) => {
          const contents = args.path === "pi-ai-compat"
            ? `export async function completeSimple() {
                globalThis.__weibeiTitleCalls = (globalThis.__weibeiTitleCalls ?? 0) + 1;
                return globalThis.__weibeiTitleResult;
              }`
            : `export const Type = new Proxy({}, { get: () => (...args) => ({ args }) });
               export const uuidv7 = () => "title-session-id";`;
          return { loader: "js", contents };
        });
      },
    }],
  });

  const extension = await import(`${pathToFileURL(outputURL).href}?v=${Date.now()}`);
  const courseRoot = join(temporaryRoot, "课程甲");
  const materialDirectory = join(courseRoot, "文稿");
  const metadataDirectory = join(courseRoot, ".weibei");
  const outsidePath = join(temporaryRoot, "课程外.txt");
  const materialPath = join(materialDirectory, "第一讲.txt");
  const linkedPath = join(materialDirectory, "偷渡.txt");
  await mkdir(materialDirectory, { recursive: true });
  await mkdir(metadataDirectory);
  await writeFile(materialPath, "ORIGINAL_EXTENSION_CONTENT");
  await writeFile(join(metadataDirectory, "secret.txt"), "INTERNAL_SECRET");
  await writeFile(outsidePath, "OUTSIDE_SECRET");
  await symlink(outsidePath, linkedPath);

  const canonicalRoot = await realpath(courseRoot);
  const canonicalMaterialPath = await realpath(materialPath);
  const canonicalOutsidePath = await realpath(outsidePath);
  const item = {
    itemID: "material-1",
    title: "第一讲",
    kind: "text",
    role: "material",
    relativePath: "文稿/第一讲.txt",
    resolvedPath: canonicalMaterialPath,
    entryIdentity: await identity(materialPath),
    targetIdentity: await identity(materialPath),
    isShared: false,
    courseIDs: ["course-a"],
    courseTitles: ["课程甲"],
    sourceRevision: "source-revision-1",
  };
  const snapshot = {
    project: {
      kind: "course",
      chatID: "chat-a",
      courseID: "course-a",
      courseTitle: "课程甲",
      rootPath: canonicalRoot,
      rootIdentity: await identity(canonicalRoot),
      items: [
        item,
        { ...item, itemID: "internal", relativePath: ".weibei/secret.txt" },
        { ...item, itemID: "linked", relativePath: "文稿/偷渡.txt" },
      ],
      isTruncated: false,
    },
  };
  const contextFile = join(temporaryRoot, "context.json");
  const hookEnvelope = {
    schemaVersion: 2,
    requestID: "request-a",
    contextRevision: "revision-a",
    answerFormPolicy: "automatic",
    purpose: "conversation",
    language: "chinese",
    question: "解释当前材料",
    material: {
      title: "第一讲",
      text: "ORIGINAL_EXTENSION_CONTENT",
      isTruncated: false,
    },
    note: { title: "当前笔记", text: "", isTruncated: false },
    selection: {
      title: "第一讲选区",
      text: "SELECTION_EXTENSION_CONTENT",
      isTruncated: false,
    },
    course: {
      title: "课程甲",
      catalog: [{
        id: "material-1",
        title: "第一讲",
        subtitle: "",
        kind: "text",
        role: "material",
        isCurrentMaterial: true,
        isCurrentNote: false,
        linkedItemIDs: [],
        tags: [],
      }],
      items: [{
        id: "material-1",
        title: "第一讲",
        subtitle: "",
        kind: "text",
        role: "material",
        isCurrentMaterial: true,
        isCurrentNote: false,
        linkedItemIDs: [],
        headings: [],
        tags: [],
        searchText: "ORIGINAL_EXTENSION_CONTENT",
        isTruncated: false,
      }],
      relations: [],
      isTruncated: false,
    },
    project: { ...snapshot.project, items: [item] },
    learning: {
      memoryRevision: 2,
      memories: [
        {
          id: "memory-progress",
          kind: "progress",
          text: "已读完第一讲",
          evidence: "当前 Chat",
          origin: "agentInference",
          status: "active",
          sessionID: "chat-a",
          createdAt: 1,
          updatedAt: 1,
        },
        {
          id: "memory-summary",
          kind: "summary",
          text: "正在建立课程框架",
          evidence: "当前 Chat",
          origin: "agentInference",
          status: "active",
          sessionID: "chat-a",
          createdAt: 2,
          updatedAt: 2,
        },
      ],
    },
    courseProfile: {
      revision: 0,
      overview: "COURSE_CARD_OVERVIEW",
      entries: [{
        id: "profile-concept-1",
        kind: "concept",
        text: "PROFILE_ENTRY_SHOULD_STAY_HIDDEN",
        sources: [{
          itemID: "material-1",
          role: "material",
          sourceRevision: "source-revision-1",
        }],
      }],
    },
  };
  await writeFile(contextFile, JSON.stringify(hookEnvelope));
  process.env.WEIBEI_AGENT_CONTEXT_FILE = contextFile;
  const eventHandlers = new Map();
  const registeredTools = new Map();
  let sessionName;
  extension.default({
    registerTool(tool) {
      registeredTools.set(tool.name, tool);
    },
    on(name, handler) {
      eventHandlers.set(name, handler);
    },
    getSessionName() {
      return sessionName;
    },
    setSessionName(value) {
      sessionName = value;
    },
  });
  const beforeAgentStart = requireValue(
    eventHandlers.get("before_agent_start"),
    "真实扩展没有注册 before_agent_start",
  );
  const beforeResult = await beforeAgentStart(
    { systemPrompt: "base" },
    {
      model: {
        provider: "openai-codex",
        api: "openai-codex-responses",
        id: "gpt-5.3-codex-spark",
      },
    },
  );
  requireValue(
      beforeResult.message === undefined &&
      beforeResult.systemPrompt.includes("直接回答用户的问题") &&
      beforeResult.systemPrompt.includes("本轮模型服务已开放原生网页搜索") &&
      beforeResult.systemPrompt.includes("location.materialItemID") &&
      beforeResult.systemPrompt.includes("weibei_course_read") &&
      beforeResult.systemPrompt.includes("weibei_course_search") &&
      beforeResult.systemPrompt.includes("weibei_course_map"),
    "本轮现场仍被写成持久消息，或本轮规则没有交给 Pi",
  );
  const agentEnd = requireValue(
    eventHandlers.get("agent_end"),
    "真实扩展没有注册首轮会话命名钩子",
  );
  globalThis.__weibeiTitleCalls = 0;
  globalThis.__weibeiTitleResult = {
    stopReason: "stop",
    content: [{ type: "text", text: "标题： 利率为何不同。" }],
  };
  const titleContext = {
    model: {
      provider: "openai-codex",
      api: "openai-codex-responses",
      id: "gpt-5.3-codex-spark",
    },
    sessionManager: {
      getBranch: () => [{ type: "message", message: { role: "user" } }],
    },
    modelRegistry: {
      getApiKeyAndHeaders: async () => ({ ok: true, apiKey: "self-check" }),
    },
  };
  await agentEnd(
    {
      messages: [{
        role: "assistant",
        stopReason: "stop",
        content: [{ type: "text", text: "利率会随资金供需变化。" }],
      }],
    },
    titleContext,
  );
  await agentEnd(
    {
      messages: [{
        role: "assistant",
        stopReason: "stop",
        content: [{ type: "text", text: "不应重复命名。" }],
      }],
    },
    titleContext,
  );
  requireValue(
    sessionName === "利率为何不同" && globalThis.__weibeiTitleCalls === 1,
    "首轮会话标题没有清洗落库，或已命名会话发生了重复请求",
  );
  requireValue(
    !registeredTools.has("weibei_context"),
    "魏碑仍注册了需要模型主动读取的上下文工具",
  );
  requireValue(
    !registeredTools.has("ls") &&
      !registeredTools.has("find") &&
      !registeredTools.has("grep"),
    "普通学习场景仍暴露重复的项目文件工具",
  );
  const providerRequestHook = requireValue(
    eventHandlers.get("before_provider_request"),
    "真实扩展没有注册模型原生网页搜索请求钩子",
  );
  const nativeSearchCases = [
    {
      name: "OpenAI Codex Responses",
      model: {
        provider: "openai-codex",
        api: "openai-codex-responses",
        id: "gpt-5.3-codex-spark",
      },
      toolType: "web_search",
    },
    {
      name: "OpenAI Responses",
      model: { provider: "openai", api: "openai-responses", id: "gpt-5.6" },
      toolType: "web_search",
    },
  ];
  for (const check of nativeSearchCases) {
    const originalPayload = {
      tools: [{ type: "function", name: "weibei_course_map", parameters: {} }],
      include: ["reasoning.encrypted_content"],
    };
    const nextPayload = await providerRequestHook(
      { payload: originalPayload },
      { model: check.model },
    );
    const tools = nextPayload?.tools ?? [];
    requireValue(
      nextPayload !== originalPayload &&
        originalPayload.tools.length === 1 &&
        tools.some((tool) => tool?.type === check.toolType) &&
        tools.some((tool) =>
          tool?.type === "function" && tool?.name === "weibei_course_map"
        ),
      `${check.name} 没有收到模型服务自己的网页搜索工具`,
    );
    requireValue(
      nextPayload.include?.includes("reasoning.encrypted_content") &&
        nextPayload.include.includes("web_search_call.action.sources"),
      `${check.name} 覆盖了原有响应内容，或没有要求模型服务返回真实搜索来源`,
    );
    const repeatedPayload = await providerRequestHook(
      { payload: nextPayload },
      { model: check.model },
    );
    requireValue(
      JSON.stringify(repeatedPayload) === JSON.stringify(nextPayload),
      `${check.name} 在同一请求中重复添加网页搜索工具`,
    );
  }
  const unsupportedSearchModels = [
    { provider: "openai", api: "openai-responses", id: "gpt-4o" },
    { provider: "google", api: "google-generative-ai", id: "gemini-3.5-flash" },
    { provider: "xai", api: "openai-responses", id: "grok-4.5" },
    { provider: "groq", api: "openai-completions", id: "openai/gpt-oss-20b" },
    { provider: "openrouter", api: "openai-completions", id: "openai/gpt-5.6" },
    { provider: "weibei-custom", api: "openai-completions", id: "local-model" },
  ];
  for (const model of unsupportedSearchModels) {
    const payload = { tools: [{ type: "function", name: "weibei_course_map" }] };
    requireValue(
      (await providerRequestHook({ payload }, { model })) === payload,
      `${model.provider}/${model.id} 被错误开放了未验证的网页搜索`,
    );
  }
  const backgroundPayload = {
    input: [{ role: "user", content: "PRIVATE_COMPACTION_TRANSCRIPT" }],
    tools: [{ type: "function", name: "summarize", parameters: {} }],
  };
  const backgroundSnapshot = JSON.stringify(backgroundPayload);
  const backgroundResult = await providerRequestHook(
    { payload: backgroundPayload },
    { model: nativeSearchCases[0].model },
  );
  requireValue(
    backgroundResult === backgroundPayload &&
      JSON.stringify(backgroundPayload) === backgroundSnapshot &&
      !backgroundResult.tools.some((tool) => tool?.type === "web_search") &&
      backgroundResult.include === undefined,
    "后台摘要请求被错误开放了网页搜索",
  );
  const webContract = await readFile(join(resourcesRoot, "system.md"), "utf8");
  requireValue(
    webContract.includes("模型自行判断是否需要搜索") &&
      webContract.includes("可点击") &&
      webContract.includes("搜索词只可包含回答当前问题所需的公开主题或实体") &&
      !webContract.includes("不得联网"),
    "网页搜索系统契约仍在禁用联网，或没有要求保留可点击来源",
  );
  requireValue(
    !registeredTools.has("weibei_ui_catalog") &&
      !registeredTools.has("weibei_compute_artifact") &&
      !registeredTools.has("weibei_rich_answer"),
    "旧生成式界面工具仍暴露给模型",
  );
  const contextHook = requireValue(
    eventHandlers.get("context"),
    "真实扩展没有注册 context 过滤器",
  );
  const filteredContext = await contextHook({
    messages: [
      { role: "custom", customType: "weibei-current-focus", content: "old", display: false },
      {
        role: "assistant",
        content: [{ type: "toolCall", id: "legacy-context", name: "weibei_context", arguments: {} }],
      },
      {
        role: "toolResult",
        toolCallId: "legacy-context",
        toolName: "weibei_context",
        content: [{ type: "text", text: "ORIGINAL_EXTENSION_CONTENT" }],
        details: { kind: "weibei_context", contextRevision: "old" },
        isError: false,
      },
      { role: "user", content: "继续" },
    ],
  });
  const transientContext = filteredContext.messages.at(-1);
  requireValue(
    filteredContext.messages.length === 2 &&
      filteredContext.messages[0]?.role === "user" &&
      transientContext?.role === "custom" &&
      transientContext.customType === "weibei-current-focus" &&
      transientContext.display === false &&
      transientContext.content.includes("revision-a") &&
      transientContext.content.includes("material-1") &&
      transientContext.content.includes("COURSE_CARD_OVERVIEW") &&
      transientContext.content.includes("SELECTION_EXTENSION_CONTENT") &&
      !transientContext.content.includes("PROFILE_ENTRY_SHOULD_STAY_HIDDEN") &&
      !transientContext.content.includes("ORIGINAL_EXTENSION_CONTENT"),
    "当前现场没有只把选区与无正文焦点作为本轮临时消息交给 Pi",
  );
  const emptyFocusEnvelope = {
    ...hookEnvelope,
    contextRevision: "context-empty",
    material: undefined,
    note: { title: "当前笔记", text: "", isTruncated: false },
    selection: undefined,
    focus: undefined,
  };
  await writeFile(contextFile, JSON.stringify(emptyFocusEnvelope));
  const clearedContext = await contextHook({
    messages: [
      { role: "custom", customType: "weibei-current-focus", content: "old", display: false },
      { role: "user", content: "现在没有打开资料" },
    ],
  });
  requireValue(
    clearedContext.messages.length === 2 &&
      clearedContext.messages[0]?.role === "user" &&
      clearedContext.messages[1]?.content.includes("context-empty") &&
      !clearedContext.messages[1]?.content.includes("ORIGINAL_EXTENSION_CONTENT"),
    "本轮现场没有替换上一轮现场，或仍携带材料正文",
  );
  const rootlessEnvelope = {
    ...hookEnvelope,
    contextRevision: "context-rootless-course",
    project: {
      ...hookEnvelope.project,
      rootPath: undefined,
      rootIdentity: undefined,
      items: [{
        ...item,
        relativePath: "",
        resolvedPath: "",
        entryIdentity: undefined,
        targetIdentity: undefined,
      }],
    },
  };
  await writeFile(contextFile, JSON.stringify(rootlessEnvelope));
  const rootlessContext = await contextHook({ messages: [] });
  requireValue(
    rootlessContext.messages.at(-1)?.content.includes("context-rootless-course") &&
      rootlessContext.messages.at(-1)?.content.includes("material-1"),
    "没有课程文件夹的旧课程无法继续建立本轮课程上下文",
  );
  await writeFile(contextFile, "{broken");
  let brokenContextRejected = false;
  try {
    await contextHook({ messages: [] });
  } catch {
    brokenContextRejected = true;
  }
  requireValue(brokenContextRejected, "回合中的损坏上下文快照被静默忽略");
  await writeFile(contextFile, JSON.stringify(hookEnvelope));

  const firstArticlePage = "完整文章上下文。".repeat(700);
  const toolCallID = "course-read-full-article";
  const toolResponseRoot = join(temporaryRoot, "tool-responses");
  await mkdir(toolResponseRoot, { recursive: true });
  const canonicalToolResponseRoot = await realpath(toolResponseRoot);
  const toolResponseDirectory = join(canonicalToolResponseRoot, hookEnvelope.requestID);
  await mkdir(toolResponseDirectory);
  process.env.WEIBEI_AGENT_TOOL_RESPONSE_DIR = canonicalToolResponseRoot;

  const courseSearchTool = requireValue(
    registeredTools.get("weibei_course_search"),
    "真实扩展没有注册课程索引搜索工具",
  );
  const profileUpdateTool = requireValue(
    registeredTools.get("weibei_course_profile_update"),
    "真实扩展没有注册课程知识档案批量更新工具",
  );
  const searchToolCallID = "course-search-only";
  await writeFile(
    join(
      toolResponseDirectory,
      `${createHash("sha256").update(searchToolCallID, "utf8").digest("hex")}.json`,
    ),
    JSON.stringify({
      schemaVersion: 1,
      requestID: hookEnvelope.requestID,
      contextRevision: hookEnvelope.contextRevision,
      toolCallID: searchToolCallID,
      toolName: "weibei_course_search",
      success: true,
      payload: {
        query: "完整文章",
        items: [{
          item: {
            ...hookEnvelope.course.items[0],
            searchText: "SEARCH_ONLY_EXCERPT",
          },
          relativePath: "文稿/第一讲.txt",
          courseIDs: ["course-a"],
          courseTitles: ["课程甲"],
          sourceRevision: "source-revision-1",
        }],
      },
    }),
  );
  await courseSearchTool.execute(searchToolCallID, { query: "完整文章" });
  let searchOnlyProfileRejected = false;
  try {
    await profileUpdateTool.execute("profile-update-after-search", {
      contextRevision: hookEnvelope.contextRevision,
      profileRevision: 0,
      checkpoint: "sectionCompleted",
      entries: [{
        kind: "concept",
        text: "只有搜索摘要，还没有读取原文。",
        sources: [{
          itemID: "material-1",
          role: "material",
          sourceRevision: "source-revision-1",
        }],
      }],
    });
  } catch {
    searchOnlyProfileRejected = true;
  }
  requireValue(
    searchOnlyProfileRejected,
    "只搜索课程索引就能把摘要沉淀为已读课程认识",
  );

  await writeFile(
    join(
      toolResponseDirectory,
      `${createHash("sha256").update(toolCallID, "utf8").digest("hex")}.json`,
    ),
    JSON.stringify({
      schemaVersion: 1,
      requestID: hookEnvelope.requestID,
      contextRevision: hookEnvelope.contextRevision,
      toolCallID,
      toolName: "weibei_course_read",
      success: true,
      payload: {
        query: "",
        items: [{
          item: {
            ...hookEnvelope.course.items[0],
            searchText: firstArticlePage,
          },
          relativePath: "文稿/第一讲.txt",
          courseIDs: ["course-a"],
          courseTitles: ["课程甲"],
          sourceRevision: "source-revision-1",
        }],
        nextCursor: "cursor-2",
        sourceRevision: "source-revision-1",
      },
    }),
  );
  const courseReadTool = requireValue(
    registeredTools.get("weibei_course_read"),
    "真实扩展没有注册课程正文读取工具",
  );
  requireValue(
    courseReadTool.description.includes("临时资料 ID"),
    "课程正文读取工具没有告诉模型使用本轮临时资料 ID",
  );
  const courseReadResult = await courseReadTool.execute(
    toolCallID,
    { itemID: "material-1", maximumCharacters: 6_000 },
  );
  requireValue(
    courseReadResult.content[0]?.text.includes('"hasMore": true') &&
      courseReadResult.content[0]?.text.includes('"nextCursor": "cursor-2"'),
    "课程正文读取工具没有把续读游标交给模型",
  );

  const continuationToolCallID = "course-read-continuation";
  await writeFile(
    join(
      toolResponseDirectory,
      `${createHash("sha256").update(continuationToolCallID, "utf8").digest("hex")}.json`,
    ),
    JSON.stringify({
      schemaVersion: 1,
      requestID: hookEnvelope.requestID,
      contextRevision: hookEnvelope.contextRevision,
      toolCallID: continuationToolCallID,
      toolName: "weibei_course_read",
      success: true,
      payload: {
        query: "",
        items: [{
          item: {
            ...hookEnvelope.course.items[0],
            searchText: "FULL_ARTICLE_TAIL_TOKEN",
          },
          relativePath: "文稿/第一讲.txt",
          courseIDs: ["course-a"],
          courseTitles: ["课程甲"],
          sourceRevision: "source-revision-1",
        }],
        sourceRevision: "source-revision-1",
      },
    }),
  );
  const continuationResult = await courseReadTool.execute(
    continuationToolCallID,
    { itemID: "material-1", cursor: "cursor-2", maximumCharacters: 6_000 },
  );
  requireValue(
    continuationResult.content[0]?.text.includes("FULL_ARTICLE_TAIL_TOKEN") &&
      continuationResult.content[0]?.text.includes('"hasMore": false'),
    "课程正文读取工具没有沿游标读到长文末尾",
  );

  const profileUpdate = await profileUpdateTool.execute("profile-update", {
    contextRevision: hookEnvelope.contextRevision,
    profileRevision: 0,
    checkpoint: "sectionCompleted",
    entries: [{
      kind: "concept",
      text: "第一讲建立了课程的基础概念。",
      sources: [{
        itemID: "material-1",
        role: "material",
        sourceRevision: "source-revision-1",
      }],
    }],
  });
  requireValue(
    profileUpdate.details?.kind === "course_profile_update",
    "课程知识档案没有在阶段性节点接收本轮真实已读来源",
  );

  const projectReadTool = requireValue(
    registeredTools.get("read"),
    "真实扩展没有复用 read 工具加载按需 Skill",
  );
  const skillRead = await projectReadTool.execute(
    "visualize-skill-read",
    { path: "skill://visualize" },
  );
  requireValue(
    skillRead.content[0]?.text.includes("# Visualize"),
    "read 工具没有按 skill:// 路径加载 visualize",
  );
  let courseFileReadRejected = false;
  try {
    await projectReadTool.execute("course-file-read", { path: "文稿/第一讲.txt" });
  } catch {
    courseFileReadRejected = true;
  }
  requireValue(courseFileReadRejected, "Skill read 仍能直接读取课程文件");
  const toolResultHook = requireValue(
    eventHandlers.get("tool_result"),
    "真实扩展没有记录按需 Skill 读取结果",
  );
  const skillMetadata = await toolResultHook({
    toolName: "read",
    isError: false,
    input: { path: "skill://visualize" },
  });
  requireValue(
    skillMetadata?.details?.kind === "weibei_skill_read" &&
      skillMetadata.details.loaded.id === "visualize",
    "按需 Skill 读取没有留下版本与哈希证据",
  );

  const normalRead = await extension.readApprovedProjectFile(snapshot, item);
  requireValue(
    normalRead.data.toString("utf8") === "ORIGINAL_EXTENSION_CONTENT",
    "真实扩展没有读取合法课程文件",
  );
  requireValue(
    extension.projectItemForPath(snapshot, "../课程外.txt") === undefined &&
      extension.projectItemForPath(snapshot, outsidePath) === undefined &&
      extension.projectItemForPath(snapshot, ".weibei/secret.txt") === undefined,
    "真实扩展接受了课程外、绝对路径或内部状态路径",
  );

  const linkedItem = {
    ...item,
    itemID: "linked",
    relativePath: "文稿/偷渡.txt",
    resolvedPath: canonicalOutsidePath,
    entryIdentity: await identity(linkedPath),
    targetIdentity: await identity(outsidePath),
  };
  let linkedReadRejected = false;
  try {
    await extension.readApprovedProjectFile(snapshot, linkedItem);
  } catch {
    linkedReadRejected = true;
  }
  requireValue(linkedReadRejected, "真实扩展把任意符号链接当成课程自有文件读取");

  const backupPath = join(dirname(materialPath), "第一讲.backup");
  const raceRead = await extension.readApprovedProjectFile(snapshot, item, async () => {
    await rename(materialPath, backupPath);
    await writeFile(materialPath, "MALICIOUS_DURING_EXTENSION_READ");
    await rm(materialPath);
    await rename(backupPath, materialPath);
  });
  requireValue(
    raceRead.data.toString("utf8") === "ORIGINAL_EXTENSION_CONTENT",
    "真实扩展在读取中路径被替换并恢复时读到了替换文件",
  );
  requireValue(
    (await readFile(materialPath, "utf8")) === "ORIGINAL_EXTENSION_CONTENT",
    "真实扩展自检没有恢复课程原文件",
  );

  process.stdout.write("WeiBei project tool extension self-check passed\n");
} finally {
  await rm(temporaryRoot, { recursive: true, force: true });
}
