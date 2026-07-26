import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const runtimeDirectory = resolve(scriptDirectory, "..");
const destinationDirectory = resolve(runtimeDirectory, "..", "..", "Sources", "WeiBei", "Resources");
const builtHTML = await readFile(resolve(runtimeDirectory, "dist", "index.html"), "utf8");
const builtCSS = await readFile(resolve(runtimeDirectory, "dist", "rich-answer-runtime.css"));
const builtJavaScript = await readFile(resolve(runtimeDirectory, "dist", "rich-answer-runtime.js"));
const checkOnly = process.argv.includes("--check");

if (
  (builtHTML.match(/<!doctype html>/gu) ?? []).length !== 1 ||
  !builtHTML.includes('src="./rich-answer-runtime.js"') ||
  !builtHTML.includes('href="./rich-answer-runtime.css"') ||
  builtHTML.includes("Content-Security-Policy")
) {
  throw new Error("built rich-answer runtime is incomplete or structurally corrupted");
}

if (
  builtJavaScript.includes(Buffer.from("旧版固定场景对照")) ||
  builtJavaScript.includes(Buffer.from("registered renderer domain contracts"))
) {
  throw new Error("production rich-answer bundle contains legacy-gallery or test-only code");
}

const resources = [
  { name: "rich-answer.html", contents: Buffer.from(builtHTML) },
  { name: "rich-answer-runtime.css", contents: builtCSS },
  { name: "rich-answer-runtime.js", contents: builtJavaScript },
];

if (checkOnly) {
  const drifted = [];
  for (const resource of resources) {
    let embedded;
    try {
      embedded = await readFile(resolve(destinationDirectory, resource.name));
    } catch {
      drifted.push(resource.name);
      continue;
    }
    if (!embedded.equals(resource.contents)) {
      drifted.push(resource.name);
    }
  }
  if (drifted.length > 0) {
    throw new Error(`embedded rich-answer resources are stale: ${drifted.join(", ")}`);
  }
  process.stdout.write("embedded rich-answer resources match the production build\n");
  process.exit(0);
}

await mkdir(destinationDirectory, { recursive: true });
await Promise.all([
  writeFile(resolve(destinationDirectory, "rich-answer.html"), builtHTML),
  copyFile(resolve(runtimeDirectory, "dist", "rich-answer-runtime.css"), resolve(destinationDirectory, "rich-answer-runtime.css")),
  copyFile(resolve(runtimeDirectory, "dist", "rich-answer-runtime.js"), resolve(destinationDirectory, "rich-answer-runtime.js")),
]);
