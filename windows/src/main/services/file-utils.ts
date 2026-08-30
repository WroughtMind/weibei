import { createHash, randomUUID } from "node:crypto";
import {
  constants,
  copyFile,
  link,
  lstat,
  mkdir,
  open,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  rmdir,
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

export interface VerifiedDirectoryIdentity {
  absolutePath: string;
  dev: bigint;
  ino: bigint;
}

export async function assertVerifiedDirectoryIdentity(
  directory: VerifiedDirectoryIdentity,
): Promise<void> {
  const [info, canonicalPath] = await Promise.all([
    lstat(directory.absolutePath, { bigint: true }),
    realpath(directory.absolutePath),
  ]);
  if (
    !info.isDirectory()
    || info.isSymbolicLink()
    || info.dev !== directory.dev
    || info.ino !== directory.ino
    || !sameFilesystemPath(canonicalPath, directory.absolutePath)
  ) {
    throw new Error("directory-identity-conflict");
  }
}

/**
 * Claim one direct child directory without following or adopting a path that
 * another process created after name selection. EEXIST is intentionally
 * surfaced so callers can retry with a fresh portable name.
 */
export async function createDirectoryExclusiveVerified(
  targetPath: string,
  expectedParentPath: string,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<VerifiedDirectoryIdentity> {
  const requestedTarget = path.resolve(targetPath);
  const requestedParent = path.resolve(expectedParentPath);
  if (!sameFilesystemPath(path.dirname(requestedTarget), requestedParent)) {
    throw new Error("directory-must-be-direct-child");
  }
  const canonicalParent = expectedParent
    ? await prepareMutationParent(requestedParent, expectedParent)
    : await realpath(requestedParent);
  const canonicalTarget = path.join(canonicalParent, path.basename(requestedTarget));
  const parentBefore = await lstat(canonicalParent, { bigint: true });
  if (!parentBefore.isDirectory() || parentBefore.isSymbolicLink()) {
    throw new Error("unsafe-directory-parent");
  }

  let created: VerifiedDirectoryIdentity | null = null;
  try {
    // recursive:false is the creation claim: it cannot adopt a directory,
    // junction, or symlink that won the same name first.
    await mkdir(canonicalTarget, { recursive: false, mode: 0o700 });
    await confirmMutationParent(expectedParent);
    const first = await lstat(canonicalTarget, { bigint: true });
    if (!first.isDirectory() || first.isSymbolicLink()) {
      throw new Error("unsafe-created-directory");
    }
    created = {
      absolutePath: canonicalTarget,
      dev: first.dev,
      ino: first.ino,
    };

    const [confirmedTarget, canonicalParentAfter, confirmed, parentAfter] = await Promise.all([
      realpath(canonicalTarget),
      realpath(requestedParent),
      lstat(canonicalTarget, { bigint: true }),
      lstat(canonicalParent, { bigint: true }),
    ]);
    if (
      !sameFilesystemPath(canonicalParentAfter, canonicalParent)
      || parentAfter.dev !== parentBefore.dev
      || parentAfter.ino !== parentBefore.ino
      || (expectedParent !== undefined
        && (parentAfter.dev !== expectedParent.dev
          || parentAfter.ino !== expectedParent.ino))
      || !confirmed.isDirectory()
      || confirmed.isSymbolicLink()
      || confirmed.dev !== first.dev
      || confirmed.ino !== first.ino
      || !sameFilesystemPath(path.dirname(confirmedTarget), canonicalParent)
    ) {
      throw new Error("directory-identity-conflict");
    }
    return { ...created, absolutePath: confirmedTarget };
  } catch (error) {
    // Only remove the exact empty directory this call claimed. A replacement
    // or a directory populated by another process is always preserved.
    if (created) {
      try {
        const current = await lstat(created.absolutePath, { bigint: true });
        if (
          current.isDirectory()
          && !current.isSymbolicLink()
          && current.dev === created.dev
          && current.ino === created.ino
        ) {
          await rmdir(created.absolutePath);
        }
      } catch {
        // Best-effort conservative cleanup.
      }
    }
    throw error;
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

export class FileWriteConflictError extends Error {
  readonly code = "write-conflict";

  constructor() {
    super("write-conflict");
    this.name = "FileWriteConflictError";
  }
}

/**
 * Replace an existing file only when its bytes still equal `expectedData`.
 *
 * The old path is first moved into an exclusively owned transaction directory,
 * then revalidated before the staged successor is placed with CREATE_NEW
 * semantics. A writer that wins any gap is preserved at the public path; the
 * displaced bytes remain in the transaction directory as conflict evidence.
 */
export async function atomicReplaceVerified(
  targetPath: string,
  expectedData: string | Uint8Array,
  nextData: string | Uint8Array,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<string> {
  const parent = await prepareMutationParent(path.dirname(targetPath), expectedParent);
  targetPath = path.join(parent, path.basename(targetPath));
  const expectedBytes = Buffer.from(expectedData);
  const nextBytes = Buffer.from(nextData);
  const transactionDirectory = path.join(
    parent,
    `.${path.basename(targetPath)}.weibei-transaction-${randomUUID()}`,
  );
  await mkdir(transactionDirectory, { recursive: false, mode: 0o700 });
  await confirmMutationParent(expectedParent);
  const transactionInfo = await lstat(transactionDirectory, { bigint: true });
  if (!transactionInfo.isDirectory() || transactionInfo.isSymbolicLink()) {
    throw new FileWriteConflictError();
  }
  const transactionIdentity: VerifiedDirectoryIdentity = {
    absolutePath: transactionDirectory,
    dev: transactionInfo.dev,
    ino: transactionInfo.ino,
  };
  const stagedPath = path.join(transactionDirectory, "next");
  const displacedPath = path.join(transactionDirectory, "previous");
  const transactionManifestPath = path.join(transactionDirectory, "transaction.json");
  const installIntentPath = path.join(transactionDirectory, "install-intent");
  const targetObservedPath = path.join(transactionDirectory, "target-observed");
  let displaced = false;
  let committed = false;

  try {
    await atomicCreateVerified(
      transactionManifestPath,
      JSON.stringify({
        schemaVersion: 1,
        targetFileName: path.basename(targetPath),
        expectedDigest: sha256(expectedBytes),
        nextDigest: sha256(nextBytes),
      }),
      transactionIdentity,
    );
    await confirmMutationParent(expectedParent);
    await assertVerifiedDirectoryIdentity(transactionIdentity);
    const handle = await open(stagedPath, "wx", 0o600);
    try {
      await handle.writeFile(nextBytes);
      await handle.sync();
    } finally {
      await handle.close();
    }
    await confirmMutationParent(expectedParent);
    await assertVerifiedDirectoryIdentity(transactionIdentity);

    const before = await readStableRegularFile(targetPath);
    if (!before.equals(expectedBytes)) throw new FileWriteConflictError();

    // `displacedPath` is inside the directory exclusively claimed above, so
    // rename cannot overwrite a path owned by another process.
    await confirmMutationParent(expectedParent);
    await rename(targetPath, displacedPath);
    displaced = true;
    await confirmMutationParent(expectedParent);
    const displacedBytes = await readStableRegularFile(displacedPath);
    if (!displacedBytes.equals(expectedBytes)) {
      await restoreDisplacedIfMissing(displacedPath, targetPath, expectedParent);
      throw new FileWriteConflictError();
    }

    // Once this durable marker exists, startup recovery must never roll the
    // public path back to `previous`: installation may already have happened.
    // A crash after intent but before placement therefore holds both versions
    // for reconciliation instead of guessing and losing a newer generation.
    await atomicCreateVerified(
      installIntentPath,
      "install-intent-v1",
      transactionIdentity,
    );
    try {
      await confirmMutationParent(expectedParent);
      await placeStagedFileExclusive(stagedPath, targetPath);
      await confirmMutationParent(expectedParent);
    } catch (error) {
      if (isNodeError(error) && error.code === "EEXIST") {
        throw new FileWriteConflictError();
      }
      throw error;
    }
    const actual = await readStableRegularFile(targetPath);
    if (!actual.equals(nextBytes)) throw new FileWriteConflictError();
    const preservedBaseline = await readStableRegularFile(displacedPath);
    if (!preservedBaseline.equals(expectedBytes)) {
      // A writer holding the old inode continued after it was moved aside.
      // Move our exact candidate out of the public path without replacing a
      // race winner, then relink that externally edited inode as live state.
      const candidatePath = path.join(transactionDirectory, "candidate");
      if (await moveExactFileAside(
        targetPath,
        candidatePath,
        nextBytes,
        expectedParent,
      )) {
        if (await relinkDisplacedAsLive(
          displacedPath,
          targetPath,
          expectedParent,
        )) {
          displaced = false;
        }
      }
      throw new FileWriteConflictError();
    }

    committed = true;
    try {
      await confirmMutationParent(expectedParent);
      await assertVerifiedDirectoryIdentity(transactionIdentity);
      await rm(displacedPath);
      displaced = false;
      await rm(stagedPath, { force: true });
      await rm(installIntentPath, { force: true });
      await rm(targetObservedPath, { force: true });
      await rm(transactionManifestPath, { force: true });
      await rmdir(transactionDirectory);
    } catch {
      // The state commit is already durable and verified. A cleanup failure
      // leaves the uniquely named transaction evidence in place.
    }
    return sha256(nextBytes);
  } catch (error) {
    if (displaced) {
      // If nobody has installed a new path, restore the captured inode without
      // replacing anything. Otherwise keep both the winner and `previous`.
      await restoreDisplacedIfMissing(displacedPath, targetPath, expectedParent)
        .catch(() => undefined);
      await markTargetObservedIfPresent(
        transactionDirectory,
        targetPath,
        transactionIdentity,
      )
        .catch(() => undefined);
    }
    await removeStageConservatively(stagedPath, transactionIdentity);
    if (!displaced && !committed) {
      await removeStageConservatively(installIntentPath, transactionIdentity);
      await removeStageConservatively(targetObservedPath, transactionIdentity);
      await removeStageConservatively(transactionManifestPath, transactionIdentity);
      try {
        await assertVerifiedDirectoryIdentity(transactionIdentity);
        await rmdir(transactionDirectory);
      } catch {
        // Preserve an ambiguous transaction directory.
      }
    }
    throw error;
  }
}

/**
 * Restore the single displaced baseline left by an interrupted
 * `atomicReplaceVerified` transaction. An existing target always wins and is
 * never replaced. Invalid or ambiguous recovery evidence fails closed.
 */
export async function recoverAtomicReplace(
  targetPath: string,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<"not-needed" | "restored" | "race-winner"> {
  const parent = await prepareMutationParent(path.dirname(targetPath), expectedParent);
  targetPath = path.join(parent, path.basename(targetPath));
  let targetExists = false;
  try {
    const target = await lstat(targetPath);
    if (!target.isFile() || target.isSymbolicLink()) {
      throw new FileWriteConflictError();
    }
    targetExists = true;
  } catch (error) {
    if (!isNodeError(error) || error.code !== "ENOENT") throw error;
  }

  const canonicalParent = await realpath(parent);
  await confirmMutationParent(expectedParent);
  const prefix = `.${path.basename(targetPath)}.weibei-transaction-`;
  const candidates: Array<{ previousPath: string; expectedDigest: string }> = [];
  for (const entry of await readdir(canonicalParent, { withFileTypes: true })) {
    if (!entry.name.startsWith(prefix)) continue;
    if (!entry.isDirectory() || entry.isSymbolicLink()) {
      throw new FileWriteConflictError();
    }
    const transactionPath = await realpath(path.join(canonicalParent, entry.name));
    if (!sameFilesystemPath(path.dirname(transactionPath), canonicalParent)) {
      throw new FileWriteConflictError();
    }
    const transactionInfo = await lstat(transactionPath, { bigint: true });
    const transactionIdentity: VerifiedDirectoryIdentity = {
      absolutePath: transactionPath,
      dev: transactionInfo.dev,
      ino: transactionInfo.ino,
    };
    const previousPath = path.join(transactionPath, "previous");
    try {
      const previous = await lstat(previousPath);
      if (!previous.isFile() || previous.isSymbolicLink()) {
        throw new FileWriteConflictError();
      }
    } catch (error) {
      if (isNodeError(error) && error.code === "ENOENT") continue;
      throw error;
    }

    if (targetExists) {
      await markTargetObserved(transactionPath, transactionIdentity);
      continue;
    }
    if (
      await verifiedMarkerExists(path.join(transactionPath, "install-intent"))
      || await verifiedMarkerExists(path.join(transactionPath, "target-observed"))
    ) {
      continue;
    }

    let manifest: unknown;
    try {
      manifest = JSON.parse((await readStableRegularFile(
        path.join(transactionPath, "transaction.json"),
      )).toString("utf8"));
    } catch {
      throw new FileWriteConflictError();
    }
    if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
      throw new FileWriteConflictError();
    }
    const record = manifest as Record<string, unknown>;
    if (
      record.schemaVersion !== 1
      || record.targetFileName !== path.basename(targetPath)
      || typeof record.expectedDigest !== "string"
      || typeof record.nextDigest !== "string"
      || !/^[0-9a-f]{64}$/u.test(record.expectedDigest)
      || !/^[0-9a-f]{64}$/u.test(record.nextDigest)
      || sha256(await readStableRegularFile(previousPath)) !== record.expectedDigest
    ) {
      throw new FileWriteConflictError();
    }
    candidates.push({
      previousPath,
      expectedDigest: record.expectedDigest,
    });
  }

  if (targetExists) return "not-needed";
  if (candidates.length === 0) return "not-needed";
  if (candidates.length !== 1) throw new FileWriteConflictError();
  const restored = await restoreDisplacedIfMissing(
    candidates[0].previousPath,
    targetPath,
    expectedParent,
  );
  if (!restored) return "race-winner";
  if (sha256(await readStableRegularFile(targetPath)) !== candidates[0].expectedDigest) {
    throw new FileWriteConflictError();
  }
  return "restored";
}

/**
 * Create a new file from fully staged bytes without ever replacing a path that
 * appeared after the caller selected its name.
 */
export async function atomicCreateVerified(
  targetPath: string,
  data: string | Uint8Array,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<string> {
  const parent = await prepareMutationParent(path.dirname(targetPath), expectedParent);
  targetPath = path.join(parent, path.basename(targetPath));
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
  await confirmMutationParent(expectedParent);

  const expected = sha256(typeof data === "string" ? Buffer.from(data) : data);
  try {
    await confirmMutationParent(expectedParent);
    await placeStagedFileExclusive(temporaryPath, targetPath);
    await confirmMutationParent(expectedParent);
  } finally {
    await removeStageConservatively(temporaryPath, expectedParent);
  }
  const actual = await sha256File(targetPath);
  if (actual !== expected) {
    // Another process may already have adopted or edited the newly created
    // path. Preserve it for reconciliation instead of deleting user data.
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

/**
 * Copy a file through a verified stage and place it without replacing an
 * existing destination. EEXIST is intentionally surfaced to the caller so it
 * can choose a fresh portable name.
 */
export async function copyFileExclusiveVerified(
  sourcePath: string,
  targetPath: string,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<string> {
  const parent = await prepareMutationParent(path.dirname(targetPath), expectedParent);
  targetPath = path.join(parent, path.basename(targetPath));
  const temporaryPath = `${targetPath}.weibei-copy-${randomUUID()}`;
  try {
    await copyFile(sourcePath, temporaryPath, constants.COPYFILE_EXCL);
    await confirmMutationParent(expectedParent);
    const [sourceDigest, copiedDigest] = await Promise.all([
      sha256File(sourcePath),
      sha256File(temporaryPath),
    ]);
    if (sourceDigest !== copiedDigest) throw new Error("copy-verification-failed");
    await confirmMutationParent(expectedParent);
    await placeStagedFileExclusive(temporaryPath, targetPath);
    await confirmMutationParent(expectedParent);
    if (await sha256File(targetPath) !== copiedDigest) {
      // The destination changed after exclusive placement. Leave it intact;
      // the course write will fail rather than register stale bytes.
      throw new Error("copy-verification-failed");
    }
    return copiedDigest;
  } finally {
    await removeStageConservatively(temporaryPath, expectedParent);
  }
}

async function placeStagedFileExclusive(
  temporaryPath: string,
  targetPath: string,
): Promise<void> {
  try {
    // A same-directory hard link is atomic and cannot replace an existing
    // destination. Filesystems without hard-link support use CREATE_NEW copy.
    await link(temporaryPath, targetPath);
  } catch (error) {
    if (isNodeError(error) && error.code === "EEXIST") throw error;
    await copyFile(temporaryPath, targetPath, constants.COPYFILE_EXCL);
  }
}

async function readStableRegularFile(filePath: string): Promise<Buffer> {
  const before = await lstat(filePath, { bigint: true });
  if (!before.isFile() || before.isSymbolicLink()) {
    throw new FileWriteConflictError();
  }
  const bytes = await readFile(filePath);
  const after = await lstat(filePath, { bigint: true });
  if (
    !after.isFile()
    || after.isSymbolicLink()
    || before.dev !== after.dev
    || before.ino !== after.ino
    || before.size !== after.size
    || before.mtimeNs !== after.mtimeNs
  ) {
    throw new FileWriteConflictError();
  }
  return bytes;
}

async function restoreDisplacedIfMissing(
  displacedPath: string,
  targetPath: string,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<boolean> {
  try {
    // Restore through a distinct staged inode. Keeping `previous` hard-linked
    // to the live target would let later evidence inspection mutate live data.
    await copyFileExclusiveVerified(displacedPath, targetPath, expectedParent);
    return true;
  } catch (error) {
    if (!isNodeError(error) || error.code !== "EEXIST") throw error;
    return false;
  }
}

async function moveExactFileAside(
  targetPath: string,
  evidencePath: string,
  expectedBytes: Buffer,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<boolean> {
  await confirmMutationParent(expectedParent);
  const before = await lstat(targetPath, { bigint: true });
  if (!before.isFile() || before.isSymbolicLink()) return false;
  if (!(await readStableRegularFile(targetPath)).equals(expectedBytes)) return false;
  await confirmMutationParent(expectedParent);
  await rename(targetPath, evidencePath);
  await confirmMutationParent(expectedParent);
  const moved = await lstat(evidencePath, { bigint: true });
  const isExpected = moved.isFile()
    && !moved.isSymbolicLink()
    && moved.dev === before.dev
    && moved.ino === before.ino
    && (await readStableRegularFile(evidencePath)).equals(expectedBytes);
  if (!isExpected) {
    await restoreDisplacedIfMissing(evidencePath, targetPath, expectedParent)
      .catch(() => undefined);
  }
  return isExpected;
}

async function relinkDisplacedAsLive(
  displacedPath: string,
  targetPath: string,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<boolean> {
  try {
    // Linking is an atomic CREATE_NEW operation and keeps a writer's already
    // open handle attached to the public state inode. Removing the evidence
    // name immediately avoids a long-lived hidden alias to live state.
    await confirmMutationParent(expectedParent);
    await link(displacedPath, targetPath);
    await confirmMutationParent(expectedParent);
    await rm(displacedPath);
    return true;
  } catch (error) {
    if (isNodeError(error) && error.code === "EEXIST") return false;
    // Filesystems without hard links restore a stable snapshot instead. Keep
    // `previous` as evidence because an open writer cannot be reattached.
    await restoreDisplacedIfMissing(displacedPath, targetPath, expectedParent);
    return false;
  }
}

async function markTargetObservedIfPresent(
  transactionPath: string,
  targetPath: string,
  transactionIdentity?: VerifiedDirectoryIdentity,
): Promise<void> {
  try {
    const target = await lstat(targetPath);
    if (!target.isFile() || target.isSymbolicLink()) return;
  } catch {
    return;
  }
  await markTargetObserved(transactionPath, transactionIdentity);
}

async function markTargetObserved(
  transactionPath: string,
  transactionIdentity?: VerifiedDirectoryIdentity,
): Promise<void> {
  const markerPath = path.join(transactionPath, "target-observed");
  try {
    await atomicCreateVerified(
      markerPath,
      "target-observed-v1",
      transactionIdentity,
    );
  } catch (error) {
    if (!isNodeError(error) || error.code !== "EEXIST") throw error;
    if (!await verifiedMarkerExists(markerPath)) {
      throw new FileWriteConflictError();
    }
  }
}

async function verifiedMarkerExists(markerPath: string): Promise<boolean> {
  try {
    const marker = await lstat(markerPath);
    if (!marker.isFile() || marker.isSymbolicLink()) {
      throw new FileWriteConflictError();
    }
    return true;
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") return false;
    throw error;
  }
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}

async function prepareMutationParent(
  parentPath: string,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<string> {
  if (!expectedParent) {
    await mkdir(parentPath, { recursive: true });
    return realpath(parentPath);
  }
  await assertVerifiedDirectoryIdentity(expectedParent);
  const canonicalParent = await realpath(parentPath);
  await assertVerifiedDirectoryIdentity(expectedParent);
  if (!sameFilesystemPath(canonicalParent, expectedParent.absolutePath)) {
    throw new Error("directory-identity-conflict");
  }
  return expectedParent.absolutePath;
}

async function confirmMutationParent(
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<void> {
  if (expectedParent) await assertVerifiedDirectoryIdentity(expectedParent);
}

async function removeStageConservatively(
  stagePath: string,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<void> {
  try {
    await confirmMutationParent(expectedParent);
    await rm(stagePath, { force: true });
  } catch {
    // A stage under an ambiguous/replaced parent is preserved for recovery.
  }
}

function sameFilesystemPath(left: string, right: string): boolean {
  return path.resolve(left).toLocaleLowerCase("en-US")
    === path.resolve(right).toLocaleLowerCase("en-US");
}

export async function isRegularFile(filePath: string): Promise<boolean> {
  try {
    return (await stat(filePath)).isFile();
  } catch {
    return false;
  }
}
