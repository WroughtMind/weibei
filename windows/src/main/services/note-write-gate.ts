import { createHash, randomUUID } from "node:crypto";
import {
  lstat,
  mkdir,
  open,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  stat,
} from "node:fs/promises";
import path from "node:path";

export const NOTE_BACKUPS_PER_ITEM = 20;
export const NOTE_BACKUP_TOTAL_BYTES = 50 * 1_024 * 1_024;

export type NoteWriteStatus = "saved" | "conflict" | "unavailable";

export interface NoteWriteRequest {
  itemId: string;
  filePath: string;
  markdown: string;
  /** Null means the caller has never observed an existing file. */
  baselineDigest: string | null;
}

export interface NoteWriteResult {
  status: NoteWriteStatus;
  /** Saved digest, or the currently observed disk digest on a conflict/hold. */
  digest: string | null;
  diskMarkdown: string | null;
  backupPath: string | null;
  reason?:
    | "baseline-required"
    | "baseline-mismatch"
    | "file-removed"
    | "unreadable"
    | "unsafe-target"
    | "write-failed";
}

export interface NoteWriteGateOptions {
  backupRootPath: string;
  maxBackupsPerItem?: number;
  maxTotalBackupBytes?: number;
  now?: () => Date;
}

export interface NoteBackupEntry {
  path: string;
  itemId: string;
  timestampMilliseconds: number;
  byteCount: number;
}

interface DiskNote {
  exists: boolean;
  bytes: Buffer | null;
  digest: string | null;
  markdown: string | null;
  mode: number;
}

/**
 * The sole note write boundary for renderer, Agent actions, rename and undo.
 *
 * Every target path shares a process-wide async mutex, including across gate
 * instances. Existing files require an exact SHA-256 baseline. The gate stages
 * bytes beside the note, checks the baseline again immediately before atomic
 * placement, rereads the result, and never reports saved before verification.
 */
export class NoteWriteGate {
  readonly backupRootPath: string;
  readonly maxBackupsPerItem: number;
  readonly maxTotalBackupBytes: number;
  private readonly now: () => Date;

  constructor(options: NoteWriteGateOptions) {
    if (!options.backupRootPath) {
      throw new TypeError("backupRootPath is required");
    }
    this.backupRootPath = path.resolve(options.backupRootPath);
    this.maxBackupsPerItem = positiveInteger(
      options.maxBackupsPerItem ?? NOTE_BACKUPS_PER_ITEM,
      "maxBackupsPerItem",
    );
    this.maxTotalBackupBytes = nonnegativeInteger(
      options.maxTotalBackupBytes ?? NOTE_BACKUP_TOTAL_BYTES,
      "maxTotalBackupBytes",
    );
    this.now = options.now ?? (() => new Date());
  }

  async write(request: NoteWriteRequest): Promise<NoteWriteResult> {
    validateRequest(request);
    const canonicalPath = await canonicalNotePath(request.filePath);
    return withNoteMutex(canonicalPath, () =>
      this.writeUnlocked({ ...request, filePath: canonicalPath }),
    );
  }

  async save(request: NoteWriteRequest): Promise<NoteWriteResult> {
    return this.write(request);
  }

  async writeNotebookMarkdownThroughGate(
    request: NoteWriteRequest,
  ): Promise<NoteWriteResult> {
    return this.write(request);
  }

  async listBackups(itemId?: string): Promise<NoteBackupEntry[]> {
    return listNoteBackups(this.backupRootPath, itemId);
  }

  private async writeUnlocked(
    request: NoteWriteRequest,
  ): Promise<NoteWriteResult> {
    const baseline = normalizeDigest(request.baselineDigest);
    let disk: DiskNote;
    try {
      disk = await readDiskNote(request.filePath);
    } catch (error) {
      return unavailableFromError(error);
    }

    if (disk.exists) {
      if (baseline === null) {
        return {
          status: "unavailable",
          digest: disk.digest,
          diskMarkdown: disk.markdown,
          backupPath: null,
          reason: "baseline-required",
        };
      }
      if (disk.digest !== baseline) {
        return {
          status: "conflict",
          digest: disk.digest,
          diskMarkdown: disk.markdown,
          backupPath: null,
          reason: "baseline-mismatch",
        };
      }
    } else if (baseline !== null) {
      return {
        status: "conflict",
        digest: null,
        diskMarkdown: null,
        backupPath: null,
        reason: "file-removed",
      };
    }

    const proposedBytes = Buffer.from(request.markdown, "utf8");
    const proposedDigest = sha256(proposedBytes);
    if (disk.exists && disk.digest === proposedDigest) {
      return {
        status: "saved",
        digest: proposedDigest,
        diskMarkdown: request.markdown,
        backupPath: null,
      };
    }

    let backupPath: string | null = null;
    if (disk.exists && disk.bytes) {
      try {
        const backup = await captureNoteBackup({
          rootPath: this.backupRootPath,
          itemId: request.itemId,
          bytes: disk.bytes,
          now: this.now(),
          maxBackupsPerItem: this.maxBackupsPerItem,
          maxTotalBackupBytes: this.maxTotalBackupBytes,
        });
        backupPath = backup.path;
      } catch {
        // Backup failure is a hard safety hold: never overwrite unprotected text.
        return {
          status: "unavailable",
          digest: disk.digest,
          diskMarkdown: disk.markdown,
          backupPath: null,
          reason: "write-failed",
        };
      }
    }

    let placement: AtomicPlacementResult;
    try {
      placement = await atomicCompareAndWrite({
        targetPath: request.filePath,
        bytes: proposedBytes,
        expectedDigest: disk.digest,
        targetMode: disk.mode,
      });
    } catch {
      const latest = await readDiskNoteOrNull(request.filePath);
      return {
        status: "unavailable",
        digest: latest?.digest ?? disk.digest,
        diskMarkdown: latest?.markdown ?? disk.markdown,
        backupPath,
        reason: "write-failed",
      };
    }

    if (!placement.placed) {
      return {
        status: "conflict",
        digest: placement.current.digest,
        diskMarkdown: placement.current.markdown,
        backupPath,
        reason: placement.current.exists
          ? "baseline-mismatch"
          : "file-removed",
      };
    }

    let verified: DiskNote;
    try {
      verified = await readDiskNote(request.filePath);
    } catch {
      return {
        status: "unavailable",
        digest: null,
        diskMarkdown: null,
        backupPath,
        reason: "write-failed",
      };
    }
    if (!verified.exists || verified.digest !== proposedDigest) {
      return {
        status: "unavailable",
        digest: verified.digest,
        diskMarkdown: verified.markdown,
        backupPath,
        reason: "write-failed",
      };
    }
    return {
      status: "saved",
      digest: proposedDigest,
      diskMarkdown: request.markdown,
      backupPath,
    };
  }
}

export function noteContentDigest(
  content: string | Uint8Array,
): string {
  return sha256(typeof content === "string" ? Buffer.from(content, "utf8") : content);
}

export function sanitizeNoteBackupItemId(raw: string): string {
  const mapped = Array.from(raw, (character) =>
    /[\p{L}\p{N}._-]/u.test(character) ? character : "_",
  )
    .join("")
    .replace(/_+/g, "_")
    .replace(/^[._]+|[._]+$/g, "");
  return Array.from(mapped || "item").slice(0, 120).join("");
}

export async function listNoteBackups(
  rootPath: string,
  itemId?: string,
): Promise<NoteBackupEntry[]> {
  const absoluteRoot = path.resolve(rootPath);
  const directories = itemId
    ? [sanitizeNoteBackupItemId(itemId)]
    : await backupDirectories(absoluteRoot);
  const result: NoteBackupEntry[] = [];
  for (const directoryName of directories) {
    const directoryPath = path.join(absoluteRoot, directoryName);
    let names: string[];
    try {
      names = await readdir(directoryPath);
    } catch {
      continue;
    }
    for (const name of names) {
      if (!name.toLocaleLowerCase("en-US").endsWith(".md")) continue;
      const backupPath = path.join(directoryPath, name);
      try {
        const info = await lstat(backupPath);
        if (info.isSymbolicLink() || !info.isFile()) continue;
        result.push({
          path: backupPath,
          itemId: directoryName,
          timestampMilliseconds:
            backupTimestampFromFileName(name) ?? info.mtimeMs,
          byteCount: info.size,
        });
      } catch {
        // A concurrent prune can remove an entry between readdir and stat.
      }
    }
  }
  return result.sort(compareBackupNewestFirst);
}

interface CaptureNoteBackupOptions {
  rootPath: string;
  itemId: string;
  bytes: Uint8Array;
  now: Date;
  maxBackupsPerItem: number;
  maxTotalBackupBytes: number;
}

export async function captureNoteBackup(
  options: CaptureNoteBackupOptions,
): Promise<NoteBackupEntry> {
  const rootPath = path.resolve(options.rootPath);
  return withBackupMutex(rootPath, () =>
    captureNoteBackupUnlocked({ ...options, rootPath }),
  );
}

async function captureNoteBackupUnlocked(
  options: CaptureNoteBackupOptions,
): Promise<NoteBackupEntry> {
  if (!Number.isFinite(options.now.getTime())) {
    throw new RangeError("Invalid backup timestamp");
  }
  const itemId = sanitizeNoteBackupItemId(options.itemId);
  const rootPath = options.rootPath;
  const noteDirectory = path.join(rootPath, itemId);
  await mkdir(noteDirectory, { recursive: true });
  const directoryInfo = await lstat(noteDirectory);
  if (directoryInfo.isSymbolicLink() || !directoryInfo.isDirectory()) {
    throw new UnsafeNoteTargetError();
  }
  const stem = windowsSafeTimestamp(options.now);
  let backupPath = path.join(noteDirectory, `${stem}.md`);
  let collision = 2;
  while (await fileExists(backupPath)) {
    backupPath = path.join(
      noteDirectory,
      `${stem}-${String(collision).padStart(2, "0")}.md`,
    );
    collision += 1;
  }
  await atomicWriteNewVerified(backupPath, options.bytes);
  const info = await stat(backupPath);
  const entry: NoteBackupEntry = {
    path: backupPath,
    itemId,
    timestampMilliseconds: options.now.getTime(),
    byteCount: info.size,
  };
  await pruneNoteBackupsUnlocked({
    rootPath,
    maxBackupsPerItem: options.maxBackupsPerItem,
    maxTotalBackupBytes: options.maxTotalBackupBytes,
  });
  return entry;
}

export async function pruneNoteBackups(options: {
  rootPath: string;
  maxBackupsPerItem?: number;
  maxTotalBackupBytes?: number;
}): Promise<void> {
  const rootPath = path.resolve(options.rootPath);
  return withBackupMutex(rootPath, () =>
    pruneNoteBackupsUnlocked({ ...options, rootPath }),
  );
}

async function pruneNoteBackupsUnlocked(options: {
  rootPath: string;
  maxBackupsPerItem?: number;
  maxTotalBackupBytes?: number;
}): Promise<void> {
  const rootPath = options.rootPath;
  const perItem = positiveInteger(
    options.maxBackupsPerItem ?? NOTE_BACKUPS_PER_ITEM,
    "maxBackupsPerItem",
  );
  const totalLimit = nonnegativeInteger(
    options.maxTotalBackupBytes ?? NOTE_BACKUP_TOTAL_BYTES,
    "maxTotalBackupBytes",
  );
  let entries = await listNoteBackups(rootPath);
  const byItem = new Map<string, NoteBackupEntry[]>();
  for (const entry of entries) {
    const group = byItem.get(entry.itemId) ?? [];
    group.push(entry);
    byItem.set(entry.itemId, group);
  }
  for (const group of byItem.values()) {
    group.sort(compareBackupNewestFirst);
    for (const excess of group.slice(perItem)) {
      await rm(excess.path, { force: true });
    }
  }
  entries = await listNoteBackups(rootPath);
  let totalBytes = entries.reduce((sum, entry) => sum + entry.byteCount, 0);
  for (const entry of entries.sort(compareBackupOldestFirst)) {
    if (totalBytes <= totalLimit) break;
    await rm(entry.path, { force: true });
    totalBytes -= entry.byteCount;
  }
  await removeEmptyBackupDirectories(rootPath);
}

interface AtomicPlacementOptions {
  targetPath: string;
  bytes: Uint8Array;
  expectedDigest: string | null;
  targetMode: number;
}

type AtomicPlacementResult =
  | { placed: true }
  | { placed: false; current: DiskNote };

async function atomicCompareAndWrite(
  options: AtomicPlacementOptions,
): Promise<AtomicPlacementResult> {
  const parent = path.dirname(options.targetPath);
  const temporaryPath = path.join(
    parent,
    `.${path.basename(options.targetPath)}.weibei-stage-${randomUUID()}`,
  );
  const handle = await open(temporaryPath, "wx", options.targetMode);
  try {
    await handle.writeFile(options.bytes);
    await handle.sync();
  } finally {
    await handle.close();
  }

  try {
    const current = await readDiskNote(options.targetPath);
    if (current.digest !== options.expectedDigest) {
      return { placed: false, current };
    }
    await rename(temporaryPath, options.targetPath);
    await syncDirectoryBestEffort(parent);
    return { placed: true };
  } finally {
    await rm(temporaryPath, { force: true });
  }
}

async function atomicWriteNewVerified(
  targetPath: string,
  bytes: Uint8Array,
): Promise<void> {
  const parent = path.dirname(targetPath);
  const temporaryPath = path.join(
    parent,
    `.${path.basename(targetPath)}.weibei-stage-${randomUUID()}`,
  );
  const handle = await open(temporaryPath, "wx", 0o600);
  try {
    await handle.writeFile(bytes);
    await handle.sync();
  } finally {
    await handle.close();
  }
  try {
    if (await fileExists(targetPath)) {
      throw new Error("backup-name-collision");
    }
    await rename(temporaryPath, targetPath);
    const verified = await readFile(targetPath);
    if (!verified.equals(Buffer.from(bytes))) {
      throw new Error("backup-write-verification-failed");
    }
    await syncDirectoryBestEffort(parent);
  } finally {
    await rm(temporaryPath, { force: true });
  }
}

async function canonicalNotePath(filePath: string): Promise<string> {
  if (!filePath || filePath.includes("\0")) {
    throw new TypeError("filePath must be a non-empty filesystem path");
  }
  const absolute = path.resolve(filePath);
  const parent = await realpath(path.dirname(absolute));
  return path.join(parent, path.basename(absolute));
}

async function readDiskNote(filePath: string): Promise<DiskNote> {
  let info: Awaited<ReturnType<typeof lstat>>;
  try {
    info = await lstat(filePath);
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") {
      return {
        exists: false,
        bytes: null,
        digest: null,
        markdown: null,
        mode: 0o600,
      };
    }
    throw error;
  }
  if (info.isSymbolicLink() || !info.isFile()) {
    throw new UnsafeNoteTargetError();
  }
  const bytes = await readFile(filePath);
  return {
    exists: true,
    bytes,
    digest: sha256(bytes),
    markdown: decodeUTF8OrNull(bytes),
    mode: info.mode & 0o777,
  };
}

async function readDiskNoteOrNull(filePath: string): Promise<DiskNote | null> {
  try {
    return await readDiskNote(filePath);
  } catch {
    return null;
  }
}

class UnsafeNoteTargetError extends Error {
  constructor() {
    super("Note target must be an ordinary non-symbolic file");
    this.name = "UnsafeNoteTargetError";
  }
}

function unavailableFromError(error: unknown): NoteWriteResult {
  return {
    status: "unavailable",
    digest: null,
    diskMarkdown: null,
    backupPath: null,
    reason: error instanceof UnsafeNoteTargetError ? "unsafe-target" : "unreadable",
  };
}

function validateRequest(request: NoteWriteRequest): void {
  if (!request.itemId) throw new TypeError("itemId is required");
  if (typeof request.markdown !== "string") {
    throw new TypeError("markdown must be a string");
  }
  if (request.baselineDigest !== null) normalizeDigest(request.baselineDigest);
}

function normalizeDigest(value: string | null): string | null {
  if (value === null) return null;
  const normalized = value.toLocaleLowerCase("en-US");
  if (!/^[a-f0-9]{64}$/.test(normalized)) {
    throw new TypeError("baselineDigest must be a SHA-256 hex digest or null");
  }
  return normalized;
}

function decodeUTF8OrNull(bytes: Uint8Array): string | null {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
  }
}

function windowsSafeTimestamp(date: Date): string {
  return date.toISOString().replaceAll(":", "-");
}

function backupTimestampFromFileName(name: string): number | null {
  const match = /^(\d{4}-\d{2}-\d{2}T)(\d{2})-(\d{2})-(\d{2}(?:\.\d+)?Z)(?:-\d+)?\.md$/i.exec(
    name,
  );
  if (!match) return null;
  const timestamp = Date.parse(`${match[1]}${match[2]}:${match[3]}:${match[4]}`);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function compareBackupNewestFirst(
  left: NoteBackupEntry,
  right: NoteBackupEntry,
): number {
  return (
    right.timestampMilliseconds - left.timestampMilliseconds ||
    right.path.localeCompare(left.path)
  );
}

function compareBackupOldestFirst(
  left: NoteBackupEntry,
  right: NoteBackupEntry,
): number {
  return (
    left.timestampMilliseconds - right.timestampMilliseconds ||
    left.path.localeCompare(right.path)
  );
}

async function backupDirectories(rootPath: string): Promise<string[]> {
  let names: string[];
  try {
    names = await readdir(rootPath);
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") return [];
    throw error;
  }
  const result: string[] = [];
  for (const name of names) {
    try {
      const info = await lstat(path.join(rootPath, name));
      if (!info.isSymbolicLink() && info.isDirectory()) result.push(name);
    } catch {
      // Concurrent pruning is harmless.
    }
  }
  return result;
}

async function removeEmptyBackupDirectories(rootPath: string): Promise<void> {
  for (const directory of await backupDirectories(rootPath)) {
    const directoryPath = path.join(rootPath, directory);
    try {
      if ((await readdir(directoryPath)).length === 0) {
        await rm(directoryPath, { recursive: false });
      }
    } catch {
      // Best effort; another capture may be using the directory.
    }
  }
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") return false;
    throw error;
  }
}

async function syncDirectoryBestEffort(parent: string): Promise<void> {
  let handle: Awaited<ReturnType<typeof open>> | undefined;
  try {
    handle = await open(parent, "r");
    await handle.sync();
  } catch {
    // Node cannot fsync a directory handle on Windows.
  } finally {
    await handle?.close().catch(() => undefined);
  }
}

function positiveInteger(value: number, name: string): number {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new RangeError(`${name} must be a positive safe integer`);
  }
  return value;
}

function nonnegativeInteger(value: number, name: string): number {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${name} must be a non-negative safe integer`);
  }
  return value;
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}

interface LockState {
  tail: Promise<void>;
  pending: number;
}

const noteLocks = new Map<string, LockState>();
const backupLocks = new Map<string, LockState>();

async function withNoteMutex<T>(
  filePath: string,
  operation: () => Promise<T>,
): Promise<T> {
  const key =
    process.platform === "win32"
      ? path.resolve(filePath).toLocaleLowerCase("en-US")
      : path.resolve(filePath);
  return withKeyedMutex(noteLocks, key, operation);
}

async function withBackupMutex<T>(
  rootPath: string,
  operation: () => Promise<T>,
): Promise<T> {
  const key =
    process.platform === "win32"
      ? path.resolve(rootPath).toLocaleLowerCase("en-US")
      : path.resolve(rootPath);
  return withKeyedMutex(backupLocks, key, operation);
}

async function withKeyedMutex<T>(
  locks: Map<string, LockState>,
  key: string,
  operation: () => Promise<T>,
): Promise<T> {
  const state = locks.get(key) ?? {
    tail: Promise.resolve(),
    pending: 0,
  };
  locks.set(key, state);
  state.pending += 1;
  const previous = state.tail.catch(() => undefined);
  let release!: () => void;
  const turn = new Promise<void>((resolve) => {
    release = resolve;
  });
  state.tail = previous.then(() => turn);
  await previous;
  try {
    return await operation();
  } finally {
    release();
    state.pending -= 1;
    if (state.pending === 0 && locks.get(key) === state) {
      locks.delete(key);
    }
  }
}
