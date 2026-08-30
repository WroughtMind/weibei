import { spawn } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { build as esbuild } from "esbuild";
import { createServer } from "vite";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const outdir = resolve(root, "dist/main");
const server = await createServer({
  configFile: resolve(root, "vite.config.ts"),
  server: { port: 5174, strictPort: true },
});

await server.listen();

const context = await esbuild({
  entryPoints: {
    index: resolve(root, "src/main/index.ts"),
    preload: resolve(root, "src/preload/index.ts"),
    "search-index-worker": resolve(root, "src/main/search-index-worker/worker.ts"),
    "agent-worker": resolve(root, "src/main/agent-worker/worker.ts"),
  },
  outdir,
  outExtension: { ".js": ".cjs" },
  bundle: true,
  platform: "node",
  target: "node24",
  format: "cjs",
  sourcemap: true,
  external: ["electron", "better-sqlite3", "electron-updater"],
});

const child = spawn(
  process.platform === "win32" ? "electron.cmd" : "electron",
  ["."],
  {
    cwd: root,
    stdio: "inherit",
    shell: process.platform === "win32",
    env: { ...process.env, WEIBEI_RENDERER_URL: server.resolvedUrls?.local[0] ?? "http://localhost:5174" },
  },
);

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, async () => {
    child.kill(signal);
    await server.close();
    process.exit(0);
  });
}

child.once("exit", async (code) => {
  await server.close();
  process.exit(code ?? 0);
});
