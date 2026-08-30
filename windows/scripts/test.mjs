import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const testRoots = ["test", "tests", "src/renderer/editor"]
  .map((name) => resolve(root, name))
  .filter(existsSync);
const tests = testRoots.flatMap((testRoot) =>
  readdirSync(testRoot, { recursive: true })
    .filter((path) => path.endsWith(".test.ts"))
    .map((path) => resolve(testRoot, path)),
);

if (tests.length === 0) {
  throw new Error("No Windows tests were discovered");
}

const result = spawnSync(
  process.execPath,
  ["--import", "tsx", "--test", ...tests],
  { cwd: root, stdio: "inherit" },
);

process.exit(result.status ?? 1);
