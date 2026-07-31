#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const inputs = JSON.parse(
  readFileSync(resolve(root, "Vendor/PiRuntime/license-review-inputs.json"), "utf8"),
);
const manifest = JSON.parse(
  readFileSync(resolve(root, "Vendor/PiRuntime/manifest.json"), "utf8"),
);
const report = readFileSync(
  resolve(root, "Docs/audit/2026-07-31-Pi-Bun运行时再分发技术复核.md"),
  "utf8",
);
const notice = readFileSync(
  resolve(root, "Vendor/PiRuntime/THIRD_PARTY_NOTICES.md"),
  "utf8",
);

const args = process.argv.slice(2);
const valueAfter = (flag) => {
  const index = args.indexOf(flag);
  if (index === -1 || !args[index + 1]) {
    throw new Error(`missing ${flag} <path>`);
  }
  return resolve(args[index + 1]);
};
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const assertEqual = (actual, expected, label) => {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${expected}, got ${actual}`);
  }
};

if (inputs.reviewStatus !== "blocked") {
  throw new Error("license review must remain blocked until external obligations are closed");
}
assertEqual(manifest.piVersion, inputs.pi.version, "Pi version");
assertEqual(manifest.sourceCommit, inputs.pi.sourceCommit, "Pi source commit");
for (const architecture of ["darwin-arm64", "darwin-x64"]) {
  const artifact = manifest.artifacts[architecture];
  if (!artifact?.archive || !/^[a-f0-9]{64}$/.test(artifact.sha256)) {
    throw new Error(`invalid ${architecture} artifact lock`);
  }
  if (!report.includes(artifact.sha256)) {
    throw new Error(`report is missing ${architecture} artifact hash`);
  }
}

const lockBytes = readFileSync(valueAfter("--pi-lock"));
assertEqual(sha256(lockBytes), inputs.pi.installLock.sha256, "Pi install lock hash");
const lock = JSON.parse(lockBytes);
const packages = Object.entries(lock.packages ?? {})
  .filter(([path]) => path)
  .map(([path, entry]) => ({
    name: entry.name ?? path.split("node_modules/").at(-1),
    version: entry.version,
    license: entry.license,
  }));
assertEqual(packages.length, inputs.pi.installLock.packageCount, "Pi locked package count");

const licenseCounts = {};
for (const entry of packages) {
  if (!entry.name || !entry.version || !entry.license) {
    throw new Error(`incomplete package entry: ${JSON.stringify(entry)}`);
  }
  licenseCounts[entry.license] = (licenseCounts[entry.license] ?? 0) + 1;
  if (!report.includes(`\`${entry.name}@${entry.version}\``)) {
    throw new Error(`report is missing ${entry.name}@${entry.version}`);
  }
}
assertEqual(
  JSON.stringify(Object.fromEntries(Object.entries(licenseCounts).sort())),
  JSON.stringify(Object.fromEntries(Object.entries(inputs.pi.installLock.licenseCounts).sort())),
  "Pi license counts",
);

const bunLicenseBytes = readFileSync(valueAfter("--bun-license"));
assertEqual(sha256(bunLicenseBytes), inputs.bun.license.sha256, "Bun license hash");
const bunLicense = bunLicenseBytes.toString("utf8");
for (const required of ["JavaScriptCore", "LGPL-2", "tinycc", "LGPL v2.1"]) {
  if (!bunLicense.includes(required)) {
    throw new Error(`Bun license is missing ${required}`);
  }
}

for (const required of [
  "G0.4 的 Pi / Bun 再分发复核当前不能标记为完成",
  inputs.pi.installLock.sha256,
  inputs.bun.license.sha256,
  "不设置或建议设置 `WEIBEI_PI_REDISTRIBUTION_REVIEWED=1`",
]) {
  if (!report.includes(required)) {
    throw new Error(`report is missing required evidence: ${required}`);
  }
}
if (!notice.includes("Before a notarized public distribution")) {
  throw new Error("Pi notice no longer records the pending redistribution review");
}

console.log(`review_status=${inputs.reviewStatus}`);
console.log(`pi_version=${inputs.pi.version}`);
console.log(`pi_locked_packages=${packages.length}`);
console.log(`pi_license_counts=${JSON.stringify(licenseCounts)}`);
console.log(`bun_version=${inputs.bun.version}`);
