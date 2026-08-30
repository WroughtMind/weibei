import { createHash } from "node:crypto";
import { realpathSync } from "node:fs";
import {
  mkdir,
  readFile,
  readdir,
  rename,
  rm,
  stat,
} from "node:fs/promises";
import path from "node:path";
import {
  assertVerifiedDirectoryIdentity,
  atomicCreateVerified,
  atomicReplaceVerified,
  FileWriteConflictError,
  recoverAtomicReplace,
  type VerifiedDirectoryIdentity,
} from "./file-utils";
import {
  decodePersistedWorkspace,
  encodePersistedWorkspace,
  type PersistedWorkspaceRecord,
} from "./swift-codec";

export const WORKSPACE_FILE_NAME = "workspace.json";
export const WORKSPACE_BACKUP_GENERATIONS = 3;
export const WORKSPACE_QUARANTINE_KEEP_COUNT = 3;

export type WorkspaceLoadSource =
  | "primary"
  | "backup-1"
  | "backup-2"
  | "backup-3"
  | "none";

export type WorkspaceRecoveryNotice =
  | "restored-from-backup"
  | "unrecoverable"
  | null;

export interface WorkspaceLoadResult {
  snapshot: PersistedWorkspaceRecord | null;
  source: WorkspaceLoadSource;
  notice: WorkspaceRecoveryNotice;
  quarantinedPath: string | null;
  /** Swift schedules a new save after applying a recovered backup. */
  needsPrimaryRewrite: boolean;
}

export interface WorkspaceSaveResult {
  digest: string;
  byteLength: number;
  /** Backup rotation is best-effort and never blocks the new primary save. */
  backupWarnings: readonly string[];
}

export interface WorkspacePersistenceOptions {
  workspaceDirectory?: string;
  primaryPath?: string;
  expectedParent?: VerifiedDirectoryIdentity;
  now?: () => Date;
}

/**
 * Durable Swift-compatible workspace snapshot storage.
 *
 * All operations on an instance are serialized. Before writing a new primary,
 * it rotates backup-2 -> 3, backup-1 -> 2, primary -> 1. The staged primary is
 * placed in the same directory, fsynced, renamed, then reread byte-for-byte and
 * decoded before the save is acknowledged.
 */
export class WorkspacePersistence {
  readonly primaryPath: string;
  private readonly now: () => Date;
  private operationQueue: Promise<void> = Promise.resolve();
  /** Exact live bytes from the last successful load/save; null means absent. */
  private primaryBaseline: Buffer | null | undefined;
  private readonly expectedParent?: VerifiedDirectoryIdentity;

  constructor(options: WorkspacePersistenceOptions | string) {
    if (typeof options === "string") {
      this.primaryPath = path.join(options, WORKSPACE_FILE_NAME);
      this.now = () => new Date();
      return;
    }
    if (options.primaryPath && options.workspaceDirectory) {
      throw new TypeError("Specify primaryPath or workspaceDirectory, not both");
    }
    let requestedPrimaryPath: string;
    if (options.primaryPath) {
      requestedPrimaryPath = path.resolve(options.primaryPath);
    } else if (options.workspaceDirectory) {
      requestedPrimaryPath = path.join(
        path.resolve(options.workspaceDirectory),
        WORKSPACE_FILE_NAME,
      );
    } else {
      throw new TypeError("workspaceDirectory or primaryPath is required");
    }
    if (options.expectedParent) {
      let canonicalRequestedParent: string;
      let canonicalExpectedParent: string;
      try {
        canonicalRequestedParent = realpathSync.native(path.dirname(requestedPrimaryPath));
        canonicalExpectedParent = realpathSync.native(options.expectedParent.absolutePath);
      } catch {
        throw new TypeError("expectedParent must own workspace.json");
      }
      if (
        !sameFilesystemPath(canonicalRequestedParent, canonicalExpectedParent)
        || !sameFilesystemPath(canonicalExpectedParent, options.expectedParent.absolutePath)
      ) {
        throw new TypeError("expectedParent must own workspace.json");
      }
      this.primaryPath = path.join(
        options.expectedParent.absolutePath,
        path.basename(requestedPrimaryPath),
      );
      this.expectedParent = { ...options.expectedParent };
    } else {
      this.primaryPath = requestedPrimaryPath;
    }
    this.now = options.now ?? (() => new Date());
  }

  backupPath(generation: 1 | 2 | 3): string {
    return workspaceBackupPath(this.primaryPath, generation);
  }

  async load(): Promise<WorkspaceLoadResult> {
    return this.runExclusive(() => this.loadUnlocked());
  }

  async loadBestAvailable(): Promise<WorkspaceLoadResult> {
    return this.load();
  }

  async save(
    snapshot: PersistedWorkspaceRecord,
  ): Promise<WorkspaceSaveResult> {
    return this.runExclusive(() => this.saveUnlocked(snapshot));
  }

  async persist(
    snapshot: PersistedWorkspaceRecord,
  ): Promise<WorkspaceSaveResult> {
    return this.save(snapshot);
  }

  private async loadUnlocked(): Promise<WorkspaceLoadResult> {
    await this.prepareParent();
    await recoverAtomicReplace(this.primaryPath, this.expectedParent);
    await this.assertParentIdentity();
    const primaryBytes = await readOptionalFile(this.primaryPath);
    await this.assertParentIdentity();
    const primaryExists = primaryBytes !== null;
    if (primaryBytes) {
      const primary = decodeValidSnapshot(primaryBytes);
      if (primary !== null) {
        this.primaryBaseline = primaryBytes;
        return {
          snapshot: primary,
          source: "primary",
          notice: null,
          quarantinedPath: null,
          needsPrimaryRewrite: false,
        };
      }
    }

    const backupExistence = await Promise.all(
      ([1, 2, 3] as const).map((generation) =>
        pathExists(this.backupPath(generation)),
      ),
    );
    await this.assertParentIdentity();
    if (!primaryExists && !backupExistence.some(Boolean)) {
      this.primaryBaseline = null;
      return {
        snapshot: null,
        source: "none",
        notice: null,
        quarantinedPath: null,
        needsPrimaryRewrite: false,
      };
    }

    const quarantinedPath = primaryExists && primaryBytes
      ? await this.quarantinePrimary(primaryBytes)
      : null;
    await this.assertParentIdentity();
    this.primaryBaseline = await readOptionalFile(this.primaryPath);
    await this.assertParentIdentity();
    for (const generation of [1, 2, 3] as const) {
      if (!backupExistence[generation - 1]) continue;
      const backup = await readValidSnapshot(this.backupPath(generation));
      await this.assertParentIdentity();
      if (backup) {
        return {
          snapshot: backup,
          source: `backup-${generation}`,
          notice: "restored-from-backup",
          quarantinedPath,
          needsPrimaryRewrite: true,
        };
      }
    }
    return {
      snapshot: null,
      source: "none",
      notice: "unrecoverable",
      quarantinedPath,
      needsPrimaryRewrite: false,
    };
  }

  private async saveUnlocked(
    snapshot: PersistedWorkspaceRecord,
  ): Promise<WorkspaceSaveResult> {
    const serialized = encodePersistedWorkspace(snapshot, {
      trailingNewline: true,
    });
    // Reject an invalid in-memory shape before disturbing the backup chain.
    decodePersistedWorkspace(serialized);
    const bytes = Buffer.from(serialized, "utf8");
    await this.prepareParent();
    if (this.primaryBaseline === undefined) {
      await recoverAtomicReplace(this.primaryPath, this.expectedParent);
      await this.assertParentIdentity();
      if (await readOptionalFile(this.primaryPath)) {
        throw new WorkspacePersistenceError(
          "baseline-required",
          "load workspace.json before replacing an existing primary",
        );
      }
      this.primaryBaseline = null;
    }
    const baseline = this.primaryBaseline;
    const backupWarnings = await rotateWorkspaceBackupHistory(
      this.primaryPath,
      baseline,
      this.expectedParent,
    );
    if (baseline === null) {
      try {
        await atomicCreateVerified(
          this.primaryPath,
          bytes,
          this.expectedParent,
        );
      } catch (error) {
        if (isNodeError(error) && error.code === "EEXIST") {
          throw new FileWriteConflictError();
        }
        throw error;
      }
    } else {
      await atomicReplaceVerified(
        this.primaryPath,
        baseline,
        bytes,
        this.expectedParent,
      );
    }

    await this.assertParentIdentity();
    const written = await readFile(this.primaryPath);
    await this.assertParentIdentity();
    if (!written.equals(bytes)) {
      throw new WorkspacePersistenceError(
        "write-verification-failed",
        "workspace.json did not match the staged bytes after placement",
      );
    }
    try {
      decodePersistedWorkspace(written);
    } catch (error) {
      throw new WorkspacePersistenceError(
        "decode-verification-failed",
        "workspace.json could not be decoded after placement",
        error,
      );
    }
    this.primaryBaseline = Buffer.from(written);
    return {
      digest: sha256(written),
      byteLength: written.byteLength,
      backupWarnings,
    };
  }

  private async quarantinePrimary(primaryBytes: Uint8Array): Promise<string | null> {
    await this.assertParentIdentity();
    const parent = path.dirname(this.primaryPath);
    const stamp = quarantineTimestamp(this.now());
    let target = path.join(parent, `workspace.corrupt-${stamp}.json`);
    let collision = 2;
    while (await pathExists(target)) {
      await this.assertParentIdentity();
      target = path.join(
        parent,
        `workspace.corrupt-${stamp}-${String(collision).padStart(2, "0")}.json`,
      );
      collision += 1;
    }
    try {
      await this.assertParentIdentity();
      if (this.expectedParent) {
        // Copy through the identity-bound exclusive creator. The corrupt live
        // file remains the exact CAS baseline for the later recovered save.
        await atomicCreateVerified(target, primaryBytes, this.expectedParent);
      } else {
        await rename(this.primaryPath, target);
      }
      await this.assertParentIdentity();
    } catch {
      // Keep trying backups. A permissions failure must not hide a usable copy.
      return null;
    }
    await pruneQuarantinedSnapshots(parent, this.expectedParent);
    return target;
  }

  private async runExclusive<T>(operation: () => Promise<T>): Promise<T> {
    const run = this.operationQueue.then(operation, operation);
    this.operationQueue = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  private async prepareParent(): Promise<void> {
    if (this.expectedParent) {
      await assertVerifiedDirectoryIdentity(this.expectedParent);
      return;
    }
    await mkdir(path.dirname(this.primaryPath), { recursive: true });
  }

  private async assertParentIdentity(): Promise<void> {
    if (this.expectedParent) {
      await assertVerifiedDirectoryIdentity(this.expectedParent);
    }
  }
}

export class WorkspacePersistenceError extends Error {
  constructor(
    readonly code:
      | "write-verification-failed"
      | "decode-verification-failed"
      | "baseline-required",
    message: string,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = "WorkspacePersistenceError";
  }
}

export function workspaceBackupPath(
  primaryPath: string,
  generation: 1 | 2 | 3,
): string {
  return path.join(
    path.dirname(primaryPath),
    `workspace.backup-${generation}.json`,
  );
}

/** Best-effort rotation, matching the Swift recovery policy. */
export async function rotateWorkspaceBackups(
  primaryPath: string,
): Promise<string[]> {
  return rotateWorkspaceBackupHistory(
    primaryPath,
    await readOptionalFile(primaryPath),
    undefined,
  );
}

async function rotateWorkspaceBackupHistory(
  primaryPath: string,
  previousPrimary: Uint8Array | null,
  expectedParent: VerifiedDirectoryIdentity | undefined,
): Promise<string[]> {
  const warnings: string[] = [];
  const backups = ([1, 2, 3] as const).map((generation) =>
    workspaceBackupPath(primaryPath, generation),
  );
  for (let index = backups.length - 1; index >= 1; index -= 1) {
    await copyReplacingBestEffort(
      backups[index - 1],
      backups[index],
      warnings,
      expectedParent,
    );
  }
  if (previousPrimary) {
    try {
      await atomicWriteExact(backups[0], previousPrimary, expectedParent);
    } catch (error) {
      warnings.push(`workspace.json -> ${path.basename(backups[0])}: ${errorMessage(error)}`);
    }
  }
  return warnings;
}

async function copyReplacingBestEffort(
  source: string,
  destination: string,
  warnings: string[],
  expectedParent: VerifiedDirectoryIdentity | undefined,
): Promise<void> {
  try {
    if (expectedParent) await assertVerifiedDirectoryIdentity(expectedParent);
    const sourceBytes = await readOptionalFile(source);
    if (expectedParent) await assertVerifiedDirectoryIdentity(expectedParent);
    if (!sourceBytes) return;
    await atomicWriteExact(destination, sourceBytes, expectedParent);
  } catch (error) {
    warnings.push(`${path.basename(source)} -> ${path.basename(destination)}: ${errorMessage(error)}`);
  }
}

async function atomicWriteExact(
  targetPath: string,
  bytes: Uint8Array,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<void> {
  if (expectedParent) await assertVerifiedDirectoryIdentity(expectedParent);
  const baseline = await readOptionalFile(targetPath);
  if (expectedParent) await assertVerifiedDirectoryIdentity(expectedParent);
  if (baseline === null) {
    await atomicCreateVerified(targetPath, bytes, expectedParent);
  } else {
    await atomicReplaceVerified(targetPath, baseline, bytes, expectedParent);
  }
}

async function readValidSnapshot(
  filePath: string,
): Promise<PersistedWorkspaceRecord | null> {
  try {
    return decodePersistedWorkspace(await readFile(filePath));
  } catch {
    return null;
  }
}

function decodeValidSnapshot(
  bytes: Uint8Array,
): PersistedWorkspaceRecord | null {
  try {
    return decodePersistedWorkspace(bytes);
  } catch {
    return null;
  }
}

async function readOptionalFile(filePath: string): Promise<Buffer | null> {
  try {
    return await readFile(filePath);
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") return null;
    throw error;
  }
}

async function pathExists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") return false;
    return true;
  }
}

async function pruneQuarantinedSnapshots(
  parent: string,
  expectedParent?: VerifiedDirectoryIdentity,
): Promise<void> {
  // Deleting by pathname cannot be made identity-bound portably. Security-
  // scoped stores retain extra quarantine evidence instead of risking removal
  // through a parent path replaced between validation and unlink.
  if (expectedParent) {
    await assertVerifiedDirectoryIdentity(expectedParent);
    return;
  }
  let names: string[];
  try {
    names = await readdir(parent);
  } catch {
    return;
  }
  const quarantined = names
    .filter(
      (name) =>
        name.startsWith("workspace.corrupt-") && name.endsWith(".json"),
    )
    .sort();
  const excess = quarantined.slice(
    0,
    Math.max(0, quarantined.length - WORKSPACE_QUARANTINE_KEEP_COUNT),
  );
  await Promise.all(
    excess.map((name) => rm(path.join(parent, name), { force: true })),
  ).catch(() => undefined);
}

function quarantineTimestamp(date: Date): string {
  if (!Number.isFinite(date.getTime())) throw new RangeError("Invalid clock date");
  const iso = date.toISOString();
  return `${iso.slice(0, 10).replaceAll("-", "")}-${iso
    .slice(11, 19)
    .replaceAll(":", "")}-${iso.slice(20, 23)}`;
}

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function sameFilesystemPath(left: string, right: string): boolean {
  return path.resolve(left).toLocaleLowerCase("en-US")
    === path.resolve(right).toLocaleLowerCase("en-US");
}
