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
    recentMessages: [],
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
  extension.default({
    registerTool() {},
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
      beforeResult.message?.customType === "weibei-current-focus" &&
      beforeResult.message?.display === false &&
      beforeResult.message?.content.includes("ORIGINAL_EXTENSION_CONTENT") &&
      beforeResult.systemPrompt.includes("直接回答用户的问题"),
    "当前材料、选区和笔记没有作为隐藏本轮焦点自然交给 Pi",
  );
  const contextHook = requireValue(
    eventHandlers.get("context"),
    "真实扩展没有注册 context 过滤器",
  );
  const filteredContext = await contextHook({
    messages: [
      { role: "custom", customType: "weibei-current-focus", content: "old", display: false },
      { role: "user", content: "继续" },
      beforeResult.message,
    ],
  });
  requireValue(
    filteredContext.messages.length === 2 &&
      filteredContext.messages.at(-1)?.content === beforeResult.message.content,
    "后续回合仍把旧焦点和当前焦点一起交给 Pi",
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
      { role: "custom", customType: "weibei-current-focus", content: beforeResult.message.content, display: false },
      { role: "user", content: "现在没有打开资料" },
    ],
  });
  requireValue(
    clearedContext.messages.length === 1 &&
      clearedContext.messages[0]?.role === "user",
    "本轮没有焦点时仍把上一轮焦点交给 Pi",
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
