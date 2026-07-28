import { copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { build as buildWithEsbuild } from "esbuild";
import { build as buildWithVite } from "vite";

import { validateBuiltRuntimeHTML } from "../Prototypes/RichAnswerWebRuntime/scripts/embed-runtime.js";

const repositoryRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));

export type ResourceBuildKind = "editor" | "oauth" | "website";

/**
 * 将仓库相对输出路径映射到指定输出根目录。
 *
 * @param outputRoot - 输出目录使用的仓库根；默认写入真实仓库
 * @param relativePath - 生成物在仓库中的固定相对路径
 * @returns 生成物的绝对路径
 */
function outputPath(outputRoot: string, relativePath: string): string {
  return resolve(outputRoot, relativePath);
}

/**
 * 构建供 WKWebView 加载的编辑器 IIFE、样式与字体。
 *
 * @param outputRoot - 输出目录使用的仓库根；默认写入真实仓库
 */
export async function buildEditor(outputRoot = repositoryRoot): Promise<void> {
  const outfile = outputPath(
    outputRoot,
    "Sources/WeiBei/Resources/Editor/editor.js",
  );
  await mkdir(dirname(outfile), { recursive: true });
  await buildWithEsbuild({
    absWorkingDir: repositoryRoot,
    entryPoints: ["Sources/WeiBei/WebEditor/src/editor.ts"],
    outfile,
    bundle: true,
    format: "iife",
    minify: true,
    sourcemap: false,
    assetNames: "fonts/[name]",
    loader: {
      ".ttf": "file",
      ".woff": "file",
      ".woff2": "file",
    },
  });
}

/**
 * 构建供 Swift 应用通过 Node 执行的 OAuth 登录脚本。
 *
 * @param outputRoot - 输出目录使用的仓库根；默认写入真实仓库
 */
export async function buildOAuth(outputRoot = repositoryRoot): Promise<void> {
  const outfile = outputPath(
    outputRoot,
    "Sources/WeiBei/Resources/pi-oauth-login.mjs",
  );
  await mkdir(dirname(outfile), { recursive: true });
  await buildWithEsbuild({
    absWorkingDir: repositoryRoot,
    entryPoints: ["tooling/pi-oauth-login.ts"],
    outfile,
    bundle: true,
    platform: "node",
    target: "node22",
    format: "esm",
    minify: false,
    sourcemap: false,
    banner: { js: "#!/usr/bin/env node" },
  });
}

/**
 * 构建官网固定加载的浏览器 JavaScript。
 *
 * @param outputRoot - 输出目录使用的仓库根；默认写入真实仓库
 */
export async function buildWebsite(outputRoot = repositoryRoot): Promise<void> {
  const outfile = outputPath(outputRoot, "website/main.js");
  await mkdir(dirname(outfile), { recursive: true });
  await buildWithEsbuild({
    absWorkingDir: repositoryRoot,
    entryPoints: ["website/main.ts"],
    outfile,
    bundle: true,
    platform: "browser",
    target: ["safari17"],
    format: "iife",
    minify: true,
    sourcemap: false,
  });
}

/**
 * 构建 Rich Answer Web Runtime，并将结果映射为应用资源。
 *
 * @param outputRoot - 输出目录使用的仓库根；默认写入真实仓库
 */
export async function buildRichAnswer(
  outputRoot = repositoryRoot,
): Promise<void> {
  const runtimeDirectory = resolve(
    repositoryRoot,
    "Prototypes/RichAnswerWebRuntime",
  );
  const buildDirectory = resolve(outputRoot, ".weibei-build/rich-answer");
  const destinationDirectory = resolve(outputRoot, "Sources/WeiBei/Resources");
  await rm(buildDirectory, { recursive: true, force: true });
  await buildWithVite({
    root: runtimeDirectory,
    logLevel: "silent",
    build: {
      outDir: buildDirectory,
      emptyOutDir: true,
    },
  });

  try {
    const builtHTML = await readFile(
      resolve(buildDirectory, "index.html"),
      "utf8",
    );
    validateBuiltRuntimeHTML(builtHTML);
    await mkdir(destinationDirectory, { recursive: true });
    await Promise.all([
      writeFile(resolve(destinationDirectory, "rich-answer.html"), builtHTML),
      copyFile(
        resolve(buildDirectory, "rich-answer-runtime.css"),
        resolve(destinationDirectory, "rich-answer-runtime.css"),
      ),
      copyFile(
        resolve(buildDirectory, "rich-answer-runtime.js"),
        resolve(destinationDirectory, "rich-answer-runtime.js"),
      ),
    ]);
  } finally {
    await rm(resolve(outputRoot, ".weibei-build"), {
      recursive: true,
      force: true,
    });
  }
}

/**
 * 按稳定命令名执行单类资源构建。
 *
 * @param kind - 要构建的资源类别
 * @param outputRoot - 输出目录使用的仓库根
 */
export async function buildResource(
  kind: ResourceBuildKind,
  outputRoot = repositoryRoot,
): Promise<void> {
  if (kind === "editor") {
    await buildEditor(outputRoot);
  } else if (kind === "oauth") {
    await buildOAuth(outputRoot);
  } else {
    await buildWebsite(outputRoot);
  }
}

/**
 * 解析命令行并执行资源构建。
 */
async function main(): Promise<void> {
  const kind = process.argv[2];
  if (kind !== "editor" && kind !== "oauth" && kind !== "website") {
    throw new Error(
      "用法：tsx tooling/build-resources.ts <editor|oauth|website>",
    );
  }
  await buildResource(kind);
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  await main();
}
