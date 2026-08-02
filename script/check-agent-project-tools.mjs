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
        builder.onResolve({ filter: /^@earendil-works\/pi-ai$/ }, () => ({
          path: "pi-ai",
          namespace: "self-check",
        }));
        builder.onLoad({ filter: /.*/, namespace: "self-check" }, () => ({
          loader: "js",
          contents:
            "export const Type = new Proxy({}, { get: () => (...args) => ({ args }) });",
        }));
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
      text: "ORIGINAL_EXTENSION_CONTENT",
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
  };
  await writeFile(contextFile, JSON.stringify(hookEnvelope));
  process.env.WEIBEI_AGENT_CONTEXT_FILE = contextFile;
  const eventHandlers = new Map();
  const registeredTools = new Map();
  extension.default({
    registerTool(tool) {
      registeredTools.set(tool.name, tool);
    },
    on(name, handler) {
      eventHandlers.set(name, handler);
    },
  });
  const beforeAgentStart = requireValue(
    eventHandlers.get("before_agent_start"),
    "真实扩展没有注册 before_agent_start",
  );
  const beforeResult = await beforeAgentStart({ systemPrompt: "base" });
  requireValue(
      beforeResult.message === undefined &&
      beforeResult.systemPrompt.includes("直接回答用户的问题") &&
      beforeResult.systemPrompt.includes("location.materialItemID") &&
      beforeResult.systemPrompt.includes("weibei_course_read") &&
      beforeResult.systemPrompt.includes("weibei_course_search") &&
      beforeResult.systemPrompt.includes("weibei_course_map"),
    "本轮现场仍被写成持久消息，或本轮规则没有交给 Pi",
  );
  requireValue(
    !registeredTools.has("weibei_context"),
    "魏碑仍注册了需要模型主动读取的上下文工具",
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
      !transientContext.content.includes("ORIGINAL_EXTENSION_CONTENT"),
    "当前现场没有只作为无正文的本轮临时消息交给 Pi",
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
  await writeFile(contextFile, "{broken");
  let brokenContextRejected = false;
  try {
    await contextHook({ messages: [] });
  } catch {
    brokenContextRejected = true;
  }
  requireValue(brokenContextRejected, "回合中的损坏上下文快照被静默忽略");
  await writeFile(contextFile, JSON.stringify(hookEnvelope));

  const fullArticle = `${"完整文章上下文。".repeat(700)}FULL_ARTICLE_TAIL_TOKEN`;
  const toolCallID = "course-read-full-article";
  const toolResponseRoot = join(temporaryRoot, "tool-responses");
  await mkdir(toolResponseRoot, { recursive: true });
  const canonicalToolResponseRoot = await realpath(toolResponseRoot);
  const toolResponseDirectory = join(canonicalToolResponseRoot, hookEnvelope.requestID);
  await mkdir(toolResponseDirectory);
  process.env.WEIBEI_AGENT_TOOL_RESPONSE_DIR = canonicalToolResponseRoot;
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
            searchText: fullArticle,
          },
          relativePath: "文稿/第一讲.txt",
          courseIDs: ["course-a"],
          courseTitles: ["课程甲"],
        }],
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
    { itemID: "material-1" },
  );
  requireValue(
    courseReadResult.content[0]?.text.includes("FULL_ARTICLE_TAIL_TOKEN"),
    "课程正文读取工具在交给模型前截掉了完整文章尾部",
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
