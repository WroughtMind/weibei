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

export const NOTE_RECOVERY_SCHEMA_VERSION = 2 as const;
export const NOTE_RECOVERY_MAX_UTF8_BYTES = 32 * 1_024 * 1_024;

export interface NoteRecoveryRecord {
  schemaVersion: typeof NOTE_RECOVERY_SCHEMA_VERSION;
  scopeHash: string;
  libraryRootPath: string;
  courseId: string;
  itemId: string;
  markdown: string;
  baselineDigest: string | null;
  savedAt: string;
}

export interface NoteRecoveryScope {
  libraryRootPath: string;
  courseId: string;
  itemId: string;
}

export interface SaveNoteRecoveryInput extends NoteRecoveryScope {
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
 * a later edit. Recovery scopes are hashed instead of embedded in paths, and ordinary
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

  async load(scope: NoteRecoveryScope): Promise<NoteRecoveryRecord | null> {
    const normalizedScope = normalizeScope(scope);
    return this.runExclusive(async () => {
      try {
        await this.ensureRoot();
        const filePath = this.filePath(normalizedScope);
        const info = await lstat(filePath);
        if (info.isSymbolicLink() || !info.isFile()) return null;
        const raw = await readFile(filePath, "utf8");
        return parseRecord(raw, normalizedScope);
      } catch {
        // A missing, damaged, or unsafe recovery file never blocks the editor.
        return null;
      }
    });
  }

  async save(input: SaveNoteRecoveryInput): Promise<NoteRecoveryRecord> {
    const scope = normalizeScope(input);
    const record = recoveryRecord({ ...input, ...scope }, this.now());
    const payload = `${JSON.stringify(record)}\n`;
    return this.runExclusive(async () => {
      await this.ensureRoot();
      const filePath = this.filePath(scope);
      await requireMissingOrRegularFile(filePath);
      await atomicWriteVerified(filePath, payload, scope);
      return structuredClone(record);
    });
  }

  async clear(scope: NoteRecoveryScope): Promise<void> {
    const normalizedScope = normalizeScope(scope);
    await this.runExclusive(async () => {
      await this.ensureRoot();
      const filePath = this.filePath(normalizedScope);
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

  private filePath(scope: NoteRecoveryScope): string {
    return path.join(this.rootPath, noteRecoveryFileName(scope));
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

export function noteRecoveryFileName(scope: NoteRecoveryScope): string {
  return `${noteRecoveryScopeHash(normalizeScope(scope))}.json`;
}

function recoveryRecord(
  input: SaveNoteRecoveryInput,
  now: Date,
): NoteRecoveryRecord {
  const scope = normalizeScope(input);
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
    scopeHash: noteRecoveryScopeHash(scope),
    libraryRootPath: scope.libraryRootPath,
    courseId: scope.courseId,
    itemId: scope.itemId,
    markdown: input.markdown,
    baselineDigest,
    savedAt: now.toISOString(),
  };
}

function parseRecord(raw: string, expectedScope: NoteRecoveryScope): NoteRecoveryRecord | null {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  const expectedScopeHash = noteRecoveryScopeHash(expectedScope);
  let recordCourseId: string;
  let recordLibraryRootPath: string;
  try {
    recordCourseId = normalizeCourseId(record.courseId);
    recordLibraryRootPath = normalizeLibraryRootPath(record.libraryRootPath);
  } catch {
    return null;
  }
  if (
    record.schemaVersion !== NOTE_RECOVERY_SCHEMA_VERSION ||
    record.scopeHash !== expectedScopeHash ||
    recordLibraryRootPath !== expectedScope.libraryRootPath ||
    recordCourseId !== expectedScope.courseId ||
    record.itemId !== expectedScope.itemId ||
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
    scopeHash: expectedScopeHash,
    libraryRootPath: expectedScope.libraryRootPath,
    courseId: expectedScope.courseId,
    itemId: expectedScope.itemId,
    markdown: record.markdown,
    baselineDigest,
    savedAt: record.savedAt,
  };
}

async function atomicWriteVerified(
  targetPath: string,
  payload: string,
  scope: NoteRecoveryScope,
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
    if (verified !== payload || parseRecord(verified, scope) === null) {
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
  if (typeof itemId !== "string" || !itemId || itemId.length > 256 || itemId.includes("\0")) {
    throw new TypeError("itemId is required");
  }
}

function normalizeScope(scope: NoteRecoveryScope): NoteRecoveryScope {
  if (!scope || typeof scope !== "object") throw new TypeError("note recovery scope is required");
  validateItemId(scope.itemId);
  return {
    libraryRootPath: normalizeLibraryRootPath(scope.libraryRootPath),
    courseId: normalizeCourseId(scope.courseId),
    itemId: scope.itemId,
  };
}

function normalizeLibraryRootPath(value: unknown): string {
  if (typeof value !== "string" || !value || value.length > 32_768 || value.includes("\0")) {
    throw new TypeError("libraryRootPath is required");
  }
  const resolved = path.resolve(value).normalize("NFC");
  return process.platform === "win32"
    ? resolved.toLocaleLowerCase("en-US")
    : resolved;
}

function normalizeCourseId(value: unknown): string {
  if (typeof value !== "string"
      || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(value)) {
    throw new TypeError("courseId must be a UUID");
  }
  return value.toLocaleLowerCase("en-US");
}

function noteRecoveryScopeHash(scope: NoteRecoveryScope): string {
  const normalized = normalizeScope(scope);
  return createHash("sha256").update(JSON.stringify([
    "weibei-note-recovery-v2",
    normalized.libraryRootPath,
    normalized.courseId,
    normalized.itemId,
  ]), "utf8").digest("hex");
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
