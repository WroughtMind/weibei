import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

const sourceDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(sourceDirectory, "..", "..", "..");
const embeddedDirectory = resolve(repositoryRoot, "Sources", "WeiBei", "Resources", "Editor");
const checkOnly = process.argv.includes("--check");
const temporaryDirectory = checkOnly
  ? await mkdtemp(resolve(tmpdir(), "weibei-editor-"))
  : undefined;
const outputDirectory = temporaryDirectory ?? embeddedDirectory;

async function generatedFiles(directory, baseDirectory = directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await generatedFiles(path, baseDirectory));
    } else if (entry.name === "editor.js" || entry.name === "editor.css" || directory.endsWith("/fonts")) {
      files.push(relative(baseDirectory, path));
    }
  }
  return files.sort();
}

try {
  await build({
    entryPoints: [resolve(sourceDirectory, "src", "editor.js")],
    bundle: true,
    format: "iife",
    outdir: outputDirectory,
    entryNames: "editor",
    assetNames: "fonts/[name]",
    minify: true,
    loader: {
      ".woff": "file",
      ".woff2": "file",
      ".ttf": "file",
    },
  });

  if (checkOnly) {
    const generated = await generatedFiles(outputDirectory);
    const embedded = await generatedFiles(embeddedDirectory);
    if (generated.join("\n") !== embedded.join("\n")) {
      throw new Error("embedded Editor generated-file set is stale");
    }
    const drifted = [];
    for (const name of generated) {
      const [built, current] = await Promise.all([
        readFile(resolve(outputDirectory, name)),
        readFile(resolve(embeddedDirectory, name)),
      ]);
      if (!built.equals(current)) drifted.push(name);
    }
    if (drifted.length > 0) {
      throw new Error(`embedded Editor resources are stale: ${drifted.join(", ")}`);
    }
    process.stdout.write("embedded Editor resources match the production build\n");
  }
} finally {
  if (temporaryDirectory) {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}
