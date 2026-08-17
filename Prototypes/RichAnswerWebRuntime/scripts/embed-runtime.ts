import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const runtimeDirectory = resolve(scriptDirectory, "..");
const destinationDirectory = resolve(runtimeDirectory, "..", "..", "Sources", "WeiBei", "Resources");
const builtHTML = await readFile(resolve(runtimeDirectory, "dist", "index.html"), "utf8");

if (
  (builtHTML.match(/<!doctype html>/gu) ?? []).length !== 1 ||
  !builtHTML.includes('src="./rich-answer-runtime.js"') ||
  !builtHTML.includes('href="./rich-answer-runtime.css"') ||
  builtHTML.includes("Content-Security-Policy")
) {
  throw new Error("built rich-answer runtime is incomplete or structurally corrupted");
}

await mkdir(destinationDirectory, { recursive: true });
await Promise.all([
  writeFile(resolve(destinationDirectory, "rich-answer.html"), builtHTML),
  copyFile(resolve(runtimeDirectory, "dist", "rich-answer-runtime.css"), resolve(destinationDirectory, "rich-answer-runtime.css")),
  copyFile(resolve(runtimeDirectory, "dist", "rich-answer-runtime.js"), resolve(destinationDirectory, "rich-answer-runtime.js")),
]);
