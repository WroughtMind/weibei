import { createHash, randomUUID } from "node:crypto";
import {
  mkdir,
  open,
  readFile,
  readdir,
  rename,
  rm,
  stat,
} from "node:fs/promises";
import path from "node:path";
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

  constructor(options: WorkspacePersistenceOptions | string) {
    if (typeof options === "string") {
      this.primaryPath = path.join(options, WORKSPACE_FILE_NAME);
      this.now = () => new Date();
      return;
    }
    if (options.primaryPath && options.workspaceDirectory) {
      throw new TypeError("Specify primaryPath or workspaceDirectory, not both");
    }
    if (options.primaryPath) {
      this.primaryPath = path.resolve(options.primaryPath);
    } else if (options.workspaceDirectory) {
      this.primaryPath = path.join(
        path.resolve(options.workspaceDirectory),
        WORKSPACE_FILE_NAME,
      );
    } else {
      throw new TypeError("workspaceDirectory or primaryPath is required");
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
    const primaryExists = await pathExists(this.primaryPath);
    if (primaryExists) {
      const primary = await readValidSnapshot(this.primaryPath);
      if (primary) {
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
    if (!primaryExists && !backupExistence.some(Boolean)) {
      return {
        snapshot: null,
        source: "none",
        notice: null,
        quarantinedPath: null,
        needsPrimaryRewrite: false,
      };
    }

    const quarantinedPath = primaryExists
      ? await this.quarantinePrimary()
      : null;
    for (const generation of [1, 2, 3] as const) {
      if (!backupExistence[generation - 1]) continue;
      const backup = await readValidSnapshot(this.backupPath(generation));
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
    await mkdir(path.dirname(this.primaryPath), { recursive: true });
    const backupWarnings = await rotateWorkspaceBackups(this.primaryPath);
    await atomicWriteExact(this.primaryPath, bytes);

    const written = await readFile(this.primaryPath);
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
    return {
      digest: sha256(written),
      byteLength: written.byteLength,
      backupWarnings,
    };
  }

  private async quarantinePrimary(): Promise<string | null> {
    const parent = path.dirname(this.primaryPath);
    const stamp = quarantineTimestamp(this.now());
    let target = path.join(parent, `workspace.corrupt-${stamp}.json`);
    let collision = 2;
    while (await pathExists(target)) {
      target = path.join(
        parent,
        `workspace.corrupt-${stamp}-${String(collision).padStart(2, "0")}.json`,
      );
      collision += 1;
    }
    try {
      await rename(this.primaryPath, target);
    } catch {
      // Keep trying backups. A permissions failure must not hide a usable copy.
      return null;
    }
    await pruneQuarantinedSnapshots(parent);
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
}

export class WorkspacePersistenceError extends Error {
  constructor(
    readonly code:
      | "write-verification-failed"
      | "decode-verification-failed",
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
  const warnings: string[] = [];
  const backups = ([1, 2, 3] as const).map((generation) =>
    workspaceBackupPath(primaryPath, generation),
  );
  for (let index = backups.length - 1; index >= 1; index -= 1) {
    await moveReplacingBestEffort(backups[index - 1], backups[index], warnings);
  }
  await moveReplacingBestEffort(primaryPath, backups[0], warnings);
  return warnings;
}

async function moveReplacingBestEffort(
  source: string,
  destination: string,
  warnings: string[],
): Promise<void> {
  if (!(await pathExists(source))) return;
  try {
    await rm(destination, { force: true });
    await rename(source, destination);
  } catch (error) {
    warnings.push(`${path.basename(source)} -> ${path.basename(destination)}: ${errorMessage(error)}`);
  }
}

async function atomicWriteExact(
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
    await rename(temporaryPath, targetPath);
    await syncDirectoryBestEffort(parent);
  } catch (error) {
    await rm(temporaryPath, { force: true });
    throw error;
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

async function pathExists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") return false;
    return true;
  }
}

async function pruneQuarantinedSnapshots(parent: string): Promise<void> {
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

async function syncDirectoryBestEffort(parent: string): Promise<void> {
  let handle: Awaited<ReturnType<typeof open>> | undefined;
  try {
    handle = await open(parent, "r");
    await handle.sync();
  } catch {
    // Directory fsync is unavailable on Windows; the file itself was fsynced.
  } finally {
    await handle?.close().catch(() => undefined);
  }
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
