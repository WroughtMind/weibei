#!/usr/bin/env -S npm exec -- tsx
import fs from "node:fs";
import path from "node:path";

const [iconset, output] = process.argv.slice(2);
if (!iconset || !output) {
  console.error("usage: build-icns.ts <AppIcon.iconset> <output.icns>");
  process.exit(2);
}

// Modern ICNS entries can contain PNG payloads directly.
const entries: ReadonlyArray<readonly [type: string, file: string]> = [
  ["icp4", "icon_16x16.png"],
  ["ic11", "icon_16x16@2x.png"],
  ["icp5", "icon_32x32.png"],
  ["ic12", "icon_32x32@2x.png"],
  ["ic07", "icon_128x128.png"],
  ["ic13", "icon_128x128@2x.png"],
  ["ic08", "icon_256x256.png"],
  ["ic14", "icon_256x256@2x.png"],
  ["ic09", "icon_512x512.png"],
  ["ic10", "icon_512x512@2x.png"],
];

/**
 * Encodes the standard iconset PNG slots as an ICNS container.
 *
 * @param iconsetPath - Directory containing the required AppIcon PNG slots
 * @param outputPath - Destination ICNS file
 */
function buildICNS(iconsetPath: string, outputPath: string): void {
  const chunks = entries.map(([type, file]) => {
    const payload = fs.readFileSync(path.join(iconsetPath, file));
    const header = Buffer.alloc(8);
    header.write(type, 0, 4, "ascii");
    header.writeUInt32BE(payload.length + 8, 4);
    return Buffer.concat([header, payload]);
  });

  const header = Buffer.alloc(8);
  header.write("icns", 0, 4, "ascii");
  header.writeUInt32BE(
    8 + chunks.reduce((sum, chunk) => sum + chunk.length, 0),
    4,
  );
  fs.writeFileSync(outputPath, Buffer.concat([header, ...chunks]));
}

buildICNS(iconset, output);
