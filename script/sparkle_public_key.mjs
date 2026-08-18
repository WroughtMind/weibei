import { createPrivateKey, createPublicKey } from "node:crypto";
import { readFileSync } from "node:fs";

const path = process.argv[2];
if (!path) throw new Error("usage: node script/sparkle_public_key.mjs <private-key-file>");

const seed = Buffer.from(readFileSync(path, "utf8").trim(), "base64");
if (seed.length !== 32) throw new Error("Sparkle private key must decode to a 32-byte Ed25519 seed");

const pkcs8Prefix = Buffer.from("302e020100300506032b657004220420", "hex");
const privateKey = createPrivateKey({
  key: Buffer.concat([pkcs8Prefix, seed]),
  format: "der",
  type: "pkcs8",
});
const publicDER = createPublicKey(privateKey).export({ format: "der", type: "spki" });
process.stdout.write(publicDER.subarray(-32).toString("base64"));
