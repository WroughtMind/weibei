#!/usr/bin/env -S npm exec -- tsx
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(process.argv[2] ?? ".");
const assets = path.join(root, "assets");
const allowed = new Set([".png", ".svg", ".ico", ".icns", ".json", ".ttf"]);

/**
 * Recursively lists files below an asset directory.
 *
 * @param dir - Directory to traverse
 * @returns Absolute paths for every descendant file
 */
function walk(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
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

fs.writeFileSync(
  path.join(assets, "asset-manifest.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
);
