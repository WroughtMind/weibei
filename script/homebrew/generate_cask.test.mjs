import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const script = new URL("./generate_cask.ts", import.meta.url);
const armSha = "a".repeat(64);
const intelSha = "b".repeat(64);

function generate() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "weibei-cask-test-"));
  const output = path.join(directory, "Casks/weibei.rb");
  const result = spawnSync(
    process.execPath,
    ["--import", "tsx", fileURLToPath(script), "1.2.3", armSha, intelSha, output],
    { encoding: "utf8" },
  );
  assert.equal(result.status, 0, result.stderr);
  return fs.readFileSync(output, "utf8");
}

test("generates architecture-specific hashes and URL", () => {
  const cask = generate();
  assert.match(cask, /arch arm: "arm64", intel: "x86_64"/);
  assert.match(cask, new RegExp(`sha256 arm: "${armSha}", intel: "${intelSha}"`));
  assert.match(cask, /WeiBei-#\{version\}-macOS-#\{arch\}\.dmg/);
  assert.doesNotMatch(cask, /depends_on arch/);
  assert.match(cask, /\n  caveats <<~EOS\n[\s\S]+\n  EOS\n/);
});
