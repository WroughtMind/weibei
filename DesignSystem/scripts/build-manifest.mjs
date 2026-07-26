#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const arguments_ = process.argv.slice(2);
const checkOnly = arguments_.includes("--check");
const rootArgument = arguments_.find((argument) => argument !== "--check") ?? ".";
const root = path.resolve(rootArgument);
const assets = path.join(root, "assets");
const allowed = new Set([".png", ".svg", ".ico", ".icns", ".json", ".ttf"]);

/**
 * Recursively returns every file below a directory.
 *
 * @param {string} directory - Directory to traverse.
 * @returns {string[]} Absolute file paths.
 */
function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}

const files = walk(assets)
  .filter((file) => allowed.has(path.extname(file).toLowerCase()))
  .filter((file) => !file.endsWith("asset-manifest.json"))
  .sort()
  .map((file) => {
    const data = fs.readFileSync(file);
    return {
      path: path.relative(root, file),
      bytes: data.length,
      sha256: crypto.createHash("sha256").update(data).digest("hex"),
    };
  });

const manifest = {
  schemaVersion: 1,
  brand: "WeiBei / 魏碑",
  version: fs.readFileSync(path.join(root, "VERSION"), "utf8").trim(),
  generatedFrom: "approved-textured-mark-1254.png + normalized SVG geometry",
  files,
};

const manifestPath = path.join(assets, "asset-manifest.json");
const expectedManifest = `${JSON.stringify(manifest, null, 2)}\n`;
if (checkOnly) {
  const actualManifest = fs.existsSync(manifestPath) ? fs.readFileSync(manifestPath, "utf8") : "";
  if (actualManifest !== expectedManifest) {
    console.error(`asset manifest is stale: ${manifestPath}`);
    console.error("run DesignSystem/scripts/build-assets.sh to regenerate approved assets and their manifest");
    process.exitCode = 1;
  }
} else {
  fs.writeFileSync(manifestPath, expectedManifest);
}
