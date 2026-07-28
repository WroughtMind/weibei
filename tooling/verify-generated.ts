import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { relative, resolve } from "node:path";

import {
  buildEditor,
  buildOAuth,
  buildRichAnswer,
  buildWebsite,
} from "./build-resources.js";

const katexFontFamilies = [
  "KaTeX_AMS-Regular",
  "KaTeX_Caligraphic-Bold",
  "KaTeX_Caligraphic-Regular",
  "KaTeX_Fraktur-Bold",
  "KaTeX_Fraktur-Regular",
  "KaTeX_Main-Bold",
  "KaTeX_Main-BoldItalic",
  "KaTeX_Main-Italic",
  "KaTeX_Main-Regular",
  "KaTeX_Math-BoldItalic",
  "KaTeX_Math-Italic",
  "KaTeX_SansSerif-Bold",
  "KaTeX_SansSerif-Italic",
  "KaTeX_SansSerif-Regular",
  "KaTeX_Script-Regular",
  "KaTeX_Size1-Regular",
  "KaTeX_Size2-Regular",
  "KaTeX_Size3-Regular",
  "KaTeX_Size4-Regular",
  "KaTeX_Typewriter-Regular",
] as const;

const expectedGeneratedFiles = [
  "Sources/WeiBei/Resources/Editor/editor.css",
  "Sources/WeiBei/Resources/Editor/editor.js",
  ...katexFontFamilies.flatMap((family) => [
    `Sources/WeiBei/Resources/Editor/fonts/${family}.ttf`,
    `Sources/WeiBei/Resources/Editor/fonts/${family}.woff`,
    `Sources/WeiBei/Resources/Editor/fonts/${family}.woff2`,
  ]),
  "Sources/WeiBei/Resources/pi-oauth-login.mjs",
  "Sources/WeiBei/Resources/rich-answer-runtime.css",
  "Sources/WeiBei/Resources/rich-answer-runtime.js",
  "Sources/WeiBei/Resources/rich-answer.html",
  "website/main.js",
].sort();

/**
 * 递归收集指定目录中的文件，并返回相对于构建根目录的稳定路径。
 *
 * @param directory - 当前遍历目录
 * @param outputRoot - 构建根目录
 * @returns 按路径排序的生成文件集合
 */
async function collectGeneratedFiles(
  directory: string,
  outputRoot: string,
): Promise<string[]> {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(
    entries.map(async (entry) => {
      const absolutePath = resolve(directory, entry.name);
      if (entry.isDirectory()) {
        return collectGeneratedFiles(absolutePath, outputRoot);
      }
      if (!entry.isFile()) {
        throw new Error(
          `生成目录包含非普通文件：${relative(outputRoot, absolutePath)}`,
        );
      }
      return [relative(outputRoot, absolutePath)];
    }),
  );
  return files.flat().sort();
}

/**
 * 计算文件内容的 SHA-256，用于跨构建目录执行严格字节比较。
 *
 * @param path - 要计算摘要的文件
 * @returns 小写十六进制 SHA-256
 */
async function sha256(path: string): Promise<string> {
  return createHash("sha256")
    .update(await readFile(path))
    .digest("hex");
}

/**
 * 在隔离输出根目录中构建全部可再生资源。
 *
 * @param outputRoot - 独立临时构建根目录
 */
async function buildAllGeneratedResources(outputRoot: string): Promise<void> {
  await Promise.all([
    buildEditor(outputRoot),
    buildOAuth(outputRoot),
    buildWebsite(outputRoot),
  ]);
  await buildRichAnswer(outputRoot);
}

/**
 * 校验单次构建只生成约定文件，避免新增、遗漏或意外临时文件被忽略。
 *
 * @param outputRoot - 独立临时构建根目录
 * @returns 已排序的实际生成文件集合
 */
async function assertExpectedFileSet(outputRoot: string): Promise<string[]> {
  const actualFiles = await collectGeneratedFiles(outputRoot, outputRoot);
  if (
    actualFiles.length !== expectedGeneratedFiles.length ||
    actualFiles.some((file, index) => file !== expectedGeneratedFiles[index])
  ) {
    const missing = expectedGeneratedFiles.filter(
      (file) => !actualFiles.includes(file),
    );
    const unexpected = actualFiles.filter(
      (file) => !expectedGeneratedFiles.includes(file),
    );
    throw new Error(
      `生成物文件集合不符合契约；缺少：[${missing.join(", ")}]；多出：[${unexpected.join(", ")}]`,
    );
  }
  return actualFiles;
}

/**
 * 使用 SHA-256 比较两个隔离构建目录中的每个约定生成物。
 *
 * @param firstRoot - 第一次构建根目录
 * @param secondRoot - 第二次构建根目录
 * @param files - 已验证的生成文件集合
 */
async function assertDeterministicHashes(
  firstRoot: string,
  secondRoot: string,
  files: string[],
): Promise<void> {
  const comparisons = await Promise.all(
    files.map(async (file) => {
      const [firstHash, secondHash] = await Promise.all([
        sha256(resolve(firstRoot, file)),
        sha256(resolve(secondRoot, file)),
      ]);
      return { file, firstHash, secondHash };
    }),
  );
  const mismatches = comparisons.filter(
    ({ firstHash, secondHash }) => firstHash !== secondHash,
  );
  if (mismatches.length > 0) {
    throw new Error(
      `生成物构建不确定：${mismatches.map(({ file, firstHash, secondHash }) => `${file} (${firstHash} != ${secondHash})`).join(", ")}`,
    );
  }
}

/**
 * 在两个独立临时目录中重建生成物，并验证文件集合与内容完全确定。
 */
async function main(): Promise<void> {
  const firstRoot = await mkdtemp(resolve(tmpdir(), "weibei-generated-first-"));
  const secondRoot = await mkdtemp(
    resolve(tmpdir(), "weibei-generated-second-"),
  );
  try {
    await buildAllGeneratedResources(firstRoot);
    const firstFiles = await assertExpectedFileSet(firstRoot);
    await buildAllGeneratedResources(secondRoot);
    const secondFiles = await assertExpectedFileSet(secondRoot);
    if (firstFiles.some((file, index) => file !== secondFiles[index])) {
      throw new Error("两次隔离构建的文件集合不一致");
    }
    await assertDeterministicHashes(firstRoot, secondRoot, firstFiles);
  } finally {
    await Promise.all([
      rm(firstRoot, { recursive: true, force: true }),
      rm(secondRoot, { recursive: true, force: true }),
    ]);
  }
}

await main();
