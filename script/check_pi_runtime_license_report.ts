#!/usr/bin/env node
/**
 * Validate Vendor/PiRuntime pins and disclosure files for Bun-compiled Pi embed.
 * Does not set WEIBEI_PI_REDISTRIBUTION_REVIEWED.
 */
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const inputs = JSON.parse(
  readFileSync(resolve(root, "Vendor/PiRuntime/license-review-inputs.json"), "utf8"),
);
const manifest = JSON.parse(
  readFileSync(resolve(root, "Vendor/PiRuntime/manifest.json"), "utf8"),
);
const notice = readFileSync(
  resolve(root, "Vendor/PiRuntime/THIRD_PARTY_NOTICES.md"),
  "utf8",
);
const bunLicensePath = resolve(root, "Vendor/PiRuntime/BUN_LICENSE.md");

const sha256 = (bytes: Buffer | string) => createHash("sha256").update(bytes).digest("hex");
const assertEqual = (actual: unknown, expected: unknown, label: string) => {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
};

const relinkFingerprint = sha256([
  inputs.pi.version,
  inputs.pi.sourceCommit,
  inputs.pi.sourceArchive.sha256,
  inputs.bun.version,
  inputs.bun.sourceCommit,
  inputs.bun.sourceArchive.sha256,
  inputs.bun.license.sha256,
  inputs.lgplRelink.webkit.sourceCommit,
  inputs.lgplRelink.webkit.sourceTree,
  inputs.lgplRelink.webkit.sourceArchive.sha256,
  inputs.lgplRelink.webkit.macosArm64Archive.sha256,
  inputs.lgplRelink.tinycc.sourceCommit,
  inputs.lgplRelink.tinycc.sourceTree,
  inputs.lgplRelink.tinycc.sourceArchive.sha256,
  ...inputs.lgplRelink.licenses.map((license: { sha256: string }) => license.sha256),
  sha256(readFileSync(resolve(root, inputs.lgplRelink.instructions))),
].join("\n"));

if (process.argv.includes("--fingerprint")) {
  console.log(relinkFingerprint);
  process.exit(0);
}

if (inputs.schemaVersion !== 3 || inputs.reviewStatus !== "disclosure-ready" || inputs.runtimeKind !== "bun-compile") {
  throw new Error("license-review-inputs must be disclosure-ready bun-compile");
}
if (manifest.runtimeKind === "node") {
  throw new Error("manifest still points at node runtime; expected Bun standalone pins");
}
assertEqual(manifest.schemaVersion, 1, "manifest schemaVersion");
assertEqual(manifest.piVersion, inputs.pi.version, "Pi version");
assertEqual(manifest.sourceCommit, inputs.pi.sourceCommit, "Pi source commit");

for (const architecture of ["darwin-arm64", "darwin-x64"]) {
  const artifact = manifest.artifacts[architecture];
  if (!artifact?.archive || !/^[a-f0-9]{64}$/.test(artifact.sha256)) {
    throw new Error(`invalid ${architecture} artifact lock`);
  }
}

if (!existsSync(bunLicensePath)) {
  throw new Error("missing Vendor/PiRuntime/BUN_LICENSE.md");
}
const bunLicenseBytes: Buffer = readFileSync(bunLicensePath);
assertEqual(sha256(bunLicenseBytes), inputs.bun.license.sha256, "Bun license hash");
const bunLicense = bunLicenseBytes.toString("utf8");
for (const required of ["JavaScriptCore", "LGPL-2", "tinycc", "LGPL v2.1", "make jsc", "zig build"]) {
  if (!bunLicense.includes(required)) {
    throw new Error(`Bun license is missing ${required}`);
  }
}

for (const license of inputs.lgplRelink.licenses) {
  const licensePath = resolve(root, license.packagedAs);
  if (!existsSync(licensePath)) {
    throw new Error(`missing ${license.packagedAs}`);
  }
  assertEqual(sha256(readFileSync(licensePath)), license.sha256, `${license.spdx} hash`);
}

const relinkInstructions = readFileSync(resolve(root, inputs.lgplRelink.instructions), "utf8");
for (const required of [
  inputs.bun.sourceCommit,
  inputs.lgplRelink.webkit.sourceCommit,
  inputs.lgplRelink.tinycc.sourceCommit,
  "bun run build:release:local",
  "bun build --compile",
  "WEIBEI_PI_RELINK_BUNDLE",
]) {
  if (!relinkInstructions.includes(required)) {
    throw new Error(`RELINK.md missing required text: ${required}`);
  }
}

for (const required of [
  "Bun `build --compile`",
  "BUN_LICENSE.md",
  "LGPL-2",
  "tinycc",
  "earendil-works/pi",
  "0.82.1",
  "WEIBEI_PI_REDISTRIBUTION_REVIEWED",
  "engineering release gate",
  "Relink / rebuild narrative",
]) {
  if (!notice.includes(required)) {
    throw new Error(`THIRD_PARTY_NOTICES.md missing required text: ${required}`);
  }
}

console.log(`review_status=${inputs.reviewStatus}`);
console.log(`runtime_kind=${inputs.runtimeKind}`);
console.log(`pi_version=${manifest.piVersion}`);
console.log(`bun_version=${inputs.bun.version}`);
console.log(`bun_license_sha256=${inputs.bun.license.sha256}`);
console.log(`relink_fingerprint=${relinkFingerprint}`);
console.log("check_pi_runtime_license_report=passed");
