import { createHash } from "node:crypto";

/**
 * Serializes JSON values with stable object-key ordering for hashing.
 */
export function canonicalJSON(value: unknown): string {
  if (value === null || typeof value === "boolean" || typeof value === "string") {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("受控计算不能包含非有限数值");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJSON(item)).join(",")}]`;
  }
  if (typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}:${canonicalJSON(item)}`);
    return `{${entries.join(",")}}`;
  }
  throw new Error("受控计算只接受 JSON 值");
}

/**
 * Hashes a UTF-8 string using the runtime's canonical SHA-256 representation.
 */
export function sha256UTF8(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

/**
 * Checks identifiers before they cross the controlled-artifact boundary.
 */
export function safeArtifactIdentifier(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/u.test(value);
}
