import { createHash, randomUUID } from "node:crypto";
import {
  lstat,
  mkdir,
  open,
  readFile,
  rename,
  rm,
} from "node:fs/promises";
import path from "node:path";

export const NOTE_RECOVERY_SCHEMA_VERSION = 1 as const;
export const NOTE_RECOVERY_MAX_UTF8_BYTES = 32 * 1_024 * 1_024;

export interface NoteRecoveryRecord {
  schemaVersion: typeof NOTE_RECOVERY_SCHEMA_VERSION;
  itemId: string;
  markdown: string;
  baselineDigest: string | null;
  savedAt: string;
}

export interface SaveNoteRecoveryInput {
  itemId: string;
  markdown: string;
  baselineDigest: string | null;
}

export interface NoteRecoveryStoreOptions {
  userDataPath: string;
  now?: () => Date;
}

/**
 * Stores unsaved editor text independently from the course library.
 *
 * Calls are ordered through one queue so a slower earlier save cannot replace
 * a later edit. Item IDs are hashed instead of embedded in paths, and ordinary
 * files are required at every path the store reads or replaces.
 */
export class NoteRecoveryStore {
  readonly rootPath: string;
  private readonly userDataPath: string;
  private readonly now: () => Date;
  private queue: Promise<void> = Promise.resolve();

  constructor(options: NoteRecoveryStoreOptions) {
    if (!options.userDataPath || options.userDataPath.includes("\0")) {
      throw new TypeError("userDataPath is required");
    }
    this.userDataPath = path.resolve(options.userDataPath);
    this.rootPath = path.join(this.userDataPath, "note-recovery");
    this.now = options.now ?? (() => new Date());
  }

  async load(itemId: string): Promise<NoteRecoveryRecord | null> {
    validateItemId(itemId);
    return this.runExclusive(async () => {
      try {
        await this.ensureRoot();
        const filePath = this.filePath(itemId);
        const info = await lstat(filePath);
        if (info.isSymbolicLink() || !info.isFile()) return null;
        const raw = await readFile(filePath, "utf8");
        return parseRecord(raw, itemId);
      } catch {
        // A missing, damaged, or unsafe recovery file never blocks the editor.
        return null;
      }
    });
  }

  async save(input: SaveNoteRecoveryInput): Promise<NoteRecoveryRecord> {
    const record = recoveryRecord(input, this.now());
    const payload = `${JSON.stringify(record)}\n`;
    return this.runExclusive(async () => {
      await this.ensureRoot();
      const filePath = this.filePath(record.itemId);
      await requireMissingOrRegularFile(filePath);
      await atomicWriteVerified(filePath, payload, record.itemId);
      return structuredClone(record);
    });
  }

  async clear(itemId: string): Promise<void> {
    validateItemId(itemId);
    await this.runExclusive(async () => {
      await this.ensureRoot();
      const filePath = this.filePath(itemId);
      let info: Awaited<ReturnType<typeof lstat>>;
      try {
        info = await lstat(filePath);
      } catch (error) {
        if (isNodeError(error) && error.code === "ENOENT") return;
        throw error;
      }
      if (info.isSymbolicLink() || !info.isFile()) {
        throw new Error("unsafe-note-recovery-target");
      }
      await rm(filePath);
    });
  }

  private filePath(itemId: string): string {
    return path.join(this.rootPath, noteRecoveryFileName(itemId));
  }

  private async ensureRoot(): Promise<void> {
    await mkdir(this.userDataPath, { recursive: true });
    await requireDirectory(this.userDataPath);
    await mkdir(this.rootPath, { recursive: true });
    await requireDirectory(this.rootPath);
  }

  private async runExclusive<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.queue.then(operation, operation);
    this.queue = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }
}

export function noteRecoveryFileName(itemId: string): string {
  validateItemId(itemId);
  return `${createHash("sha256").update(itemId, "utf8").digest("hex")}.json`;
}

function recoveryRecord(
  input: SaveNoteRecoveryInput,
  now: Date,
): NoteRecoveryRecord {
  validateItemId(input.itemId);
  if (typeof input.markdown !== "string") {
    throw new TypeError("markdown must be a string");
  }
  if (Buffer.byteLength(input.markdown, "utf8") > NOTE_RECOVERY_MAX_UTF8_BYTES) {
    throw new RangeError("markdown exceeds note recovery limit");
  }
  const baselineDigest = normalizeDigest(input.baselineDigest);
  if (!Number.isFinite(now.getTime())) throw new RangeError("invalid savedAt");
  return {
    schemaVersion: NOTE_RECOVERY_SCHEMA_VERSION,
    itemId: input.itemId,
    markdown: input.markdown,
    baselineDigest,
    savedAt: now.toISOString(),
  };
}

function parseRecord(raw: string, expectedItemId: string): NoteRecoveryRecord | null {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (
    record.schemaVersion !== NOTE_RECOVERY_SCHEMA_VERSION ||
    record.itemId !== expectedItemId ||
    typeof record.markdown !== "string" ||
    Buffer.byteLength(record.markdown, "utf8") > NOTE_RECOVERY_MAX_UTF8_BYTES ||
    typeof record.savedAt !== "string" ||
    !Number.isFinite(Date.parse(record.savedAt))
  ) {
    return null;
  }
  let baselineDigest: string | null;
  try {
    baselineDigest = normalizeDigest(record.baselineDigest);
  } catch {
    return null;
  }
  return {
    schemaVersion: NOTE_RECOVERY_SCHEMA_VERSION,
    itemId: expectedItemId,
    markdown: record.markdown,
    baselineDigest,
    savedAt: record.savedAt,
  };
}

async function atomicWriteVerified(
  targetPath: string,
  payload: string,
  itemId: string,
): Promise<void> {
  const temporaryPath = path.join(
    path.dirname(targetPath),
    `.${path.basename(targetPath)}.stage-${randomUUID()}`,
  );
  const handle = await open(temporaryPath, "wx", 0o600);
  try {
    await handle.writeFile(payload, "utf8");
    await handle.sync();
  } finally {
    await handle.close();
  }
  try {
    await requireMissingOrRegularFile(targetPath);
    await rename(temporaryPath, targetPath);
    const verifiedInfo = await lstat(targetPath);
    if (verifiedInfo.isSymbolicLink() || !verifiedInfo.isFile()) {
      throw new Error("note-recovery-write-verification-failed");
    }
    const verified = await readFile(targetPath, "utf8");
    if (verified !== payload || parseRecord(verified, itemId) === null) {
      throw new Error("note-recovery-write-verification-failed");
    }
  } finally {
    await rm(temporaryPath, { force: true });
  }
}

async function requireDirectory(directoryPath: string): Promise<void> {
  const info = await lstat(directoryPath);
  if (info.isSymbolicLink() || !info.isDirectory()) {
    throw new Error("unsafe-note-recovery-directory");
  }
}

async function requireMissingOrRegularFile(filePath: string): Promise<void> {
  try {
    const info = await lstat(filePath);
    if (info.isSymbolicLink() || !info.isFile()) {
      throw new Error("unsafe-note-recovery-target");
    }
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") return;
    throw error;
  }
}

function validateItemId(itemId: string): void {
  if (typeof itemId !== "string" || !itemId || itemId.includes("\0")) {
    throw new TypeError("itemId is required");
  }
}

function normalizeDigest(value: unknown): string | null {
  if (value === null) return null;
  if (typeof value !== "string" || !/^[a-fA-F0-9]{64}$/.test(value)) {
    throw new TypeError("baselineDigest must be a SHA-256 hex digest or null");
  }
  return value.toLocaleLowerCase("en-US");
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}
