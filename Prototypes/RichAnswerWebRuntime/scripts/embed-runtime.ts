import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export interface EmbeddedRuntimePaths {
  runtimeDirectory: string;
  destinationDirectory: string;
}

/**
 * Resolves build input and App resource output paths from this script's location.
 */
export function resolveEmbeddedRuntimePaths(
  moduleURL: string = import.meta.url,
): EmbeddedRuntimePaths {
  const scriptDirectory = dirname(fileURLToPath(moduleURL));
  const runtimeDirectory = resolve(scriptDirectory, "..");
  return {
    runtimeDirectory,
    destinationDirectory: resolve(
      runtimeDirectory,
      "..",
      "..",
      "Sources",
      "WeiBei",
      "Resources",
    ),
  };
}

/**
 * Rejects incomplete HTML before any generated App resource is replaced.
 */
export function validateBuiltRuntimeHTML(builtHTML: string): void {
  if (
    (builtHTML.match(/<!doctype html>/gu) ?? []).length !== 1 ||
    !builtHTML.includes('src="./rich-answer-runtime.js"') ||
    !builtHTML.includes('href="./rich-answer-runtime.css"') ||
    builtHTML.includes("Content-Security-Policy")
  ) {
    throw new Error(
      "built rich-answer runtime is incomplete or structurally corrupted",
    );
  }
}

/**
 * Copies a validated Vite build into the App's generated resource directory.
 */
export async function embedRuntime(
  paths: EmbeddedRuntimePaths = resolveEmbeddedRuntimePaths(),
): Promise<void> {
  const builtHTML = await readFile(
    resolve(paths.runtimeDirectory, "dist", "index.html"),
    "utf8",
  );
  validateBuiltRuntimeHTML(builtHTML);

  await mkdir(paths.destinationDirectory, { recursive: true });
  await Promise.all([
    writeFile(
      resolve(paths.destinationDirectory, "rich-answer.html"),
      builtHTML,
    ),
    copyFile(
      resolve(paths.runtimeDirectory, "dist", "rich-answer-runtime.css"),
      resolve(paths.destinationDirectory, "rich-answer-runtime.css"),
    ),
    copyFile(
      resolve(paths.runtimeDirectory, "dist", "rich-answer-runtime.js"),
      resolve(paths.destinationDirectory, "rich-answer-runtime.js"),
    ),
  ]);
}

/**
 * Identifies direct CLI execution while keeping imports side-effect free for tests.
 */
function isDirectExecution(moduleURL: string = import.meta.url): boolean {
  const entryPath = process.argv[1];
  return (
    entryPath !== undefined &&
    pathToFileURL(resolve(entryPath)).href === moduleURL
  );
}

if (isDirectExecution()) {
  await embedRuntime();
}
