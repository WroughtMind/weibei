import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  embedRuntime,
  validateBuiltRuntimeHTML,
  type EmbeddedRuntimePaths,
} from "../scripts/embed-runtime";

const temporaryDirectories: string[] = [];

/**
 * Creates isolated build and destination directories for embed tests.
 */
async function makeRuntimePaths(): Promise<EmbeddedRuntimePaths> {
  const root = await mkdtemp(resolve(tmpdir(), "weibei-rich-answer-runtime-"));
  temporaryDirectories.push(root);
  const runtimeDirectory = resolve(root, "runtime");
  const destinationDirectory = resolve(root, "resources");
  await mkdir(resolve(runtimeDirectory, "dist"), { recursive: true });
  return { runtimeDirectory, destinationDirectory };
}

afterEach(async () => {
  await Promise.all(
    temporaryDirectories
      .splice(0)
      .map((directory) => rm(directory, { force: true, recursive: true })),
  );
});

describe("embedRuntime", () => {
  it("publishes the complete validated runtime", async () => {
    const paths = await makeRuntimePaths();
    const builtHTML = [
      "<!doctype html>",
      '<link rel="stylesheet" href="./rich-answer-runtime.css">',
      '<script defer src="./rich-answer-runtime.js"></script>',
    ].join("\n");
    await Promise.all([
      writeFile(
        resolve(paths.runtimeDirectory, "dist", "index.html"),
        builtHTML,
      ),
      writeFile(
        resolve(paths.runtimeDirectory, "dist", "rich-answer-runtime.css"),
        "body{}",
      ),
      writeFile(
        resolve(paths.runtimeDirectory, "dist", "rich-answer-runtime.js"),
        "void 0;",
      ),
    ]);

    await embedRuntime(paths);

    await expect(
      readFile(resolve(paths.destinationDirectory, "rich-answer.html"), "utf8"),
    ).resolves.toBe(builtHTML);
    await expect(
      readFile(
        resolve(paths.destinationDirectory, "rich-answer-runtime.css"),
        "utf8",
      ),
    ).resolves.toBe("body{}");
    await expect(
      readFile(
        resolve(paths.destinationDirectory, "rich-answer-runtime.js"),
        "utf8",
      ),
    ).resolves.toBe("void 0;");
  });

  it("rejects malformed output before creating the destination", () => {
    expect(() => validateBuiltRuntimeHTML("<!doctype html>")).toThrow(
      "built rich-answer runtime is incomplete or structurally corrupted",
    );
  });
});
