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
