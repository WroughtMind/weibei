import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { cp, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { build as esbuild } from "esbuild";
import { build as viteBuild } from "vite";

const windowsRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const repositoryRoot = resolve(windowsRoot, "..");
const rendererOutdir = resolve(windowsRoot, "dist/renderer");
const mainOutdir = resolve(windowsRoot, "dist/main");
const canonicalResources = resolve(repositoryRoot, "Sources/WeiBei/Resources");

const run = (command, args, cwd) => new Promise((resolveRun, rejectRun) => {
  const child = spawn(command, args, { cwd, stdio: "inherit" });
  child.once("error", rejectRun);
  child.once("exit", (code, signal) => {
    if (code === 0) {
      resolveRun();
      return;
    }
    rejectRun(new Error(
      `${command} ${args.join(" ")} failed${signal ? ` with ${signal}` : ` with exit code ${code}`}`,
    ));
  });
});

const windowsEditorHostHTML = (canonicalHTML) => {
  const startMarker = "  <script>\n    var weiBeiEntry = document.createElement('script');";
  const endMarker = "    document.body.appendChild(weiBeiEntry);\n  </script>";
  const start = canonicalHTML.indexOf(startMarker);
  const endStart = canonicalHTML.indexOf(endMarker, start);
  if (start < 0 || endStart < 0) {
    throw new Error("Canonical Editor/index.html entry loader marker changed");
  }
  const end = endStart + endMarker.length;
  const hostHTML = `${canonicalHTML.slice(0, start)}  <script src="./windows-host-bridge.js"></script>${canonicalHTML.slice(end)}`;
  const scriptHashes = [...hostHTML.matchAll(/<script>([\s\S]*?)<\/script>/g)]
    .map((match) => `'sha256-${createHash("sha256").update(match[1]).digest("base64")}'`);
  if (scriptHashes.length === 0) {
    throw new Error("Windows editor host has no canonical inline scripts to authorize");
  }
  const csp = [
    "default-src 'none'",
    `script-src 'self' ${scriptHashes.join(" ")}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: weibeiimage:",
    "font-src 'self' data:",
    "connect-src 'none'",
    "worker-src 'self' blob:",
    "object-src 'none'",
    "media-src 'none'",
    "form-action 'none'",
    "base-uri 'self'",
  ].join("; ");
  return hostHTML
    .replace("<head>", `<head>\n  <meta http-equiv="Content-Security-Policy" content="${csp}">`);
};

const verifyCopiedEditorResources = async () => {
  const manifest = JSON.parse(await readFile(
    resolve(canonicalResources, "Editor/editor-resources.json"),
    "utf8",
  ));
  if (manifest.schemaVersion !== 1 || !Array.isArray(manifest.assets)) {
    throw new Error("Unsupported canonical editor resource manifest");
  }
  for (const asset of manifest.assets) {
    if (typeof asset.name !== "string"
        || !asset.name
        || asset.name.includes("\\")
        || asset.name.split("/").includes("..")) {
      throw new Error("Unsafe canonical editor resource name");
    }
    const destination = resolve(rendererOutdir, "Editor", asset.name);
    const bytes = await readFile(destination);
    const digest = createHash("sha256").update(bytes).digest("hex");
    if (bytes.byteLength !== asset.bytes || digest !== asset.sha256) {
      throw new Error(`Copied canonical editor resource differs: ${asset.name}`);
    }
  }

  const fontNames = await readdir(resolve(canonicalResources, "Fonts"));
  for (const name of fontNames) {
    const source = resolve(canonicalResources, "Fonts", name);
    if (!(await stat(source)).isFile()) continue;
    const [sourceBytes, destinationBytes] = await Promise.all([
      readFile(source),
      readFile(resolve(rendererOutdir, "Fonts", name)),
    ]);
    if (!sourceBytes.equals(destinationBytes)) {
      throw new Error(`Copied canonical font differs: ${name}`);
    }
  }
};

// There is one owner for Milkdown/KaTeX/Mermaid/Prism output on both platforms.
await run(process.execPath, ["script/build_editor.mjs"], repositoryRoot);

await viteBuild({ configFile: resolve(windowsRoot, "vite.config.ts") });
await Promise.all([
  rm(resolve(rendererOutdir, "Editor"), { recursive: true, force: true }),
  rm(resolve(rendererOutdir, "Fonts"), { recursive: true, force: true }),
]);
await Promise.all([
  cp(resolve(canonicalResources, "Editor"), resolve(rendererOutdir, "Editor"), { recursive: true }),
  cp(resolve(canonicalResources, "Fonts"), resolve(rendererOutdir, "Fonts"), { recursive: true }),
]);
await verifyCopiedEditorResources();

await esbuild({
  entryPoints: [resolve(windowsRoot, "src/renderer/editor/frame-bridge.ts")],
  outfile: resolve(rendererOutdir, "Editor/windows-host-bridge.js"),
  bundle: true,
  platform: "browser",
  target: "es2023",
  format: "iife",
  sourcemap: false,
});
const canonicalEditorHTML = await readFile(
  resolve(rendererOutdir, "Editor/index.html"),
  "utf8",
);
await writeFile(
  resolve(rendererOutdir, "Editor/windows-host.html"),
  windowsEditorHostHTML(canonicalEditorHTML),
);

await mkdir(mainOutdir, { recursive: true });

await esbuild({
  entryPoints: {
    index: resolve(windowsRoot, "src/main/index.ts"),
    preload: resolve(windowsRoot, "src/preload/index.ts"),
    "search-index-worker": resolve(windowsRoot, "src/main/search-index-worker/worker.ts"),
    "agent-worker": resolve(windowsRoot, "src/main/agent-worker/worker.ts"),
  },
  outdir: mainOutdir,
  outExtension: { ".js": ".cjs" },
  bundle: true,
  platform: "node",
  target: "node24",
  format: "cjs",
  sourcemap: false,
  external: ["electron", "better-sqlite3", "electron-updater"],
});
