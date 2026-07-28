import { rm } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const generatedPaths = [
  "Prototypes/RichAnswerWebRuntime/dist",
  "Sources/WeiBei/Resources/Editor/editor.css",
  "Sources/WeiBei/Resources/Editor/editor.js",
  "Sources/WeiBei/Resources/Editor/fonts",
  "Sources/WeiBei/Resources/pi-oauth-login.mjs",
  "Sources/WeiBei/Resources/rich-answer.html",
  "Sources/WeiBei/Resources/rich-answer-runtime.css",
  "Sources/WeiBei/Resources/rich-answer-runtime.js",
  "website/main.js",
];

/**
 * 删除可由 TypeScript 源码重建的本地生成物。
 */
async function main(): Promise<void> {
  await Promise.all(
    generatedPaths.map((relativePath) =>
      rm(resolve(repositoryRoot, relativePath), {
        recursive: true,
        force: true,
      }),
    ),
  );
}

await main();
