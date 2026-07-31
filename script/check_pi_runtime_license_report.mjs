#!/usr/bin/env node
/**
 * Validate Vendor/PiRuntime pins for the Node-based embedded Pi runtime.
 * Does not download archives; does not set WEIBEI_PI_REDISTRIBUTION_REVIEWED.
 */
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
const notice = readFileSync(
  resolve(root, "Vendor/PiRuntime/THIRD_PARTY_NOTICES.md"),
  "utf8",
);

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const assertEqual = (actual, expected, label) => {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
};

if (inputs.runtimeKind !== "node" || inputs.reviewStatus !== "node-runtime") {
  throw new Error("license review inputs must describe the Node runtime path");
}
assertEqual(manifest.runtimeKind, "node", "manifest runtimeKind");
assertEqual(manifest.schemaVersion, 2, "manifest schemaVersion");
assertEqual(manifest.piVersion, inputs.pi.version, "Pi version");
assertEqual(manifest.npmPackage, inputs.pi.npmPackage, "npm package");
assertEqual(manifest.sourceCommit, inputs.pi.sourceCommit, "Pi source commit");
assertEqual(manifest.node?.version, inputs.node.version, "Node version");

for (const architecture of ["darwin-arm64", "darwin-x64"]) {
  const fromManifest = manifest.node.artifacts[architecture];
  const fromInputs = inputs.node.artifacts[architecture];
  assertEqual(fromManifest.archive, fromInputs.archive, `${architecture} archive`);
  assertEqual(fromManifest.sha256, fromInputs.sha256, `${architecture} sha256`);
  assertEqual(fromManifest.url, fromInputs.url, `${architecture} url`);
  if (!/^[a-f0-9]{64}$/.test(fromManifest.sha256)) {
    throw new Error(`invalid ${architecture} node sha256`);
  }
}

for (const required of [
  "Node.js",
  "@earendil-works/pi-coding-agent",
  "does **not** embed the Bun-compiled",
  "0.82.1",
  "22.19.0",
]) {
  if (!notice.includes(required)) {
    throw new Error(`Pi notice is missing required text: ${required}`);
  }
}

// Negative self-check: ensure we still refuse the old Bun single-file story as "complete".
if (notice.includes("Bun-compiled single-file") && notice.includes("does **not** embed")) {
  // ok
} else {
  throw new Error("notice must explicitly reject Bun single-file redistribution");
}

console.log(`review_status=${inputs.reviewStatus}`);
console.log(`runtime_kind=${manifest.runtimeKind}`);
console.log(`pi_version=${manifest.piVersion}`);
console.log(`npm_package=${manifest.npmPackage}`);
console.log(`node_version=${manifest.node.version}`);
console.log(`node_sha256_arm64=${manifest.node.artifacts["darwin-arm64"].sha256}`);
console.log("check_pi_runtime_license_report=passed");
