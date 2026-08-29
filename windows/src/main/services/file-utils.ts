import { createHash, randomUUID } from "node:crypto";
import {
  copyFile,
  mkdir,
  open,
  readFile,
  realpath,
  rename,
  rm,
  stat,
} from "node:fs/promises";
import path from "node:path";

const windowsReservedName = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$/i;

export function portablePath(parts: readonly string[]): string {
  return parts.join("/");
}

export function validatePortableRelativePath(value: string): string {
  if (!value || value.includes("\\") || path.posix.isAbsolute(value)) {
    throw new Error("unsafe-relative-path");
  }
  const parts = value.split("/");
  if (
    parts.some(
      (part) =>
        !part ||
        part === "." ||
        part === ".." ||
        part.startsWith(".") ||
        part.endsWith(".") ||
        part.endsWith(" ") ||
        windowsReservedName.test(part),
    )
  ) {
    throw new Error("unsafe-relative-path");
  }
  return parts.join("/");
}

export function safeFileName(raw: string, fallback: string): string {
  const normalized = raw
    .normalize("NFC")
    .replace(/[<>:"/\\|?*\u0000-\u001f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[. ]+$/g, "")
    .slice(0, 96);
  if (!normalized || windowsReservedName.test(normalized)) return fallback;
  return normalized;
}

export async function resolveExistingInside(
  root: string,
  relativePath: string,
): Promise<string> {
  const portable = validatePortableRelativePath(relativePath);
  const [canonicalRoot, canonicalTarget] = await Promise.all([
    realpath(root),
    realpath(path.join(root, ...portable.split("/"))),
  ]);
  assertInside(canonicalRoot, canonicalTarget);
  return canonicalTarget;
}

export async function resolveNewInside(
  root: string,
  relativePath: string,
): Promise<string> {
  const portable = validatePortableRelativePath(relativePath);
  const candidate = path.join(root, ...portable.split("/"));
  const [canonicalRoot, canonicalParent] = await Promise.all([
    realpath(root),
    realpath(path.dirname(candidate)),
  ]);
  assertInside(canonicalRoot, canonicalParent);
  return path.join(canonicalParent, path.basename(candidate));
}

export function assertInside(root: string, target: string): void {
  const normalizedRoot = path.resolve(root).toLocaleLowerCase("en-US");
  const normalizedTarget = path.resolve(target).toLocaleLowerCase("en-US");
  const prefix = normalizedRoot.endsWith(path.sep)
    ? normalizedRoot
    : normalizedRoot + path.sep;
  if (normalizedTarget !== normalizedRoot && !normalizedTarget.startsWith(prefix)) {
    throw new Error("path-outside-capability-root");
  }
}

export function sha256(data: string | Uint8Array): string {
  return createHash("sha256").update(data).digest("hex");
}

export async function sha256File(filePath: string): Promise<string> {
  return sha256(await readFile(filePath));
}

export async function atomicWriteVerified(
  targetPath: string,
  data: string | Uint8Array,
): Promise<string> {
  const parent = path.dirname(targetPath);
  await mkdir(parent, { recursive: true });
  const temporaryPath = path.join(
    parent,
    `.${path.basename(targetPath)}.weibei-stage-${randomUUID()}`,
  );
  const handle = await open(temporaryPath, "wx", 0o600);
  try {
    await handle.writeFile(data);
    await handle.sync();
  } finally {
    await handle.close();
  }

  const expected = sha256(typeof data === "string" ? Buffer.from(data) : data);
  try {
    await rename(temporaryPath, targetPath);
  } catch (error) {
    await rm(temporaryPath, { force: true });
    throw error;
  }
  const actual = await sha256File(targetPath);
  if (actual !== expected) {
    throw new Error("write-verification-failed");
  }
  return actual;
}

export async function copyFileVerified(
  sourcePath: string,
  targetPath: string,
): Promise<string> {
  const temporaryPath = `${targetPath}.weibei-copy-${randomUUID()}`;
  await mkdir(path.dirname(targetPath), { recursive: true });
  try {
    await copyFile(sourcePath, temporaryPath);
    const [sourceDigest, copiedDigest] = await Promise.all([
      sha256File(sourcePath),
      sha256File(temporaryPath),
    ]);
    if (sourceDigest !== copiedDigest) throw new Error("copy-verification-failed");
    await rename(temporaryPath, targetPath);
    return copiedDigest;
  } catch (error) {
    await rm(temporaryPath, { force: true });
    throw error;
  }
}

export async function isRegularFile(filePath: string): Promise<boolean> {
  try {
    return (await stat(filePath)).isFile();
  } catch {
    return false;
  }
}
