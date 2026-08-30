import { randomUUID } from "node:crypto";
import type { BigIntStats } from "node:fs";
import {
  lstat,
  mkdir,
  readFile,
  readdir,
  realpath,
  rm,
  rmdir,
} from "node:fs/promises";
import path from "node:path";
import type {
  CourseDetail,
  CourseSummary,
  DocumentPayload,
  StudyItem,
  StudyItemKind,
} from "../../shared/contracts";
import {
  atomicCreateVerified,
  atomicReplaceVerified,
  assertInside,
  copyFileExclusiveVerified,
  createDirectoryExclusiveVerified,
  recoverAtomicReplace,
  resolveExistingInside,
  safeFileName,
  sha256,
  sha256File,
  FileWriteConflictError,
  type VerifiedDirectoryIdentity,
  validatePortableRelativePath,
} from "./file-utils";
import {
  dateFromSwiftReferenceSeconds,
  parseSwiftJSON,
  stringifySwiftJSON,
  swiftReferenceSecondsFromDate,
  type SwiftJSONObject,
  type SwiftJSONValue,
} from "./swift-codec";

export const COURSE_MANIFEST_RELATIVE_PATH = ".weibei/course.json";
export const COURSE_STATE_RELATIVE_PATH = ".weibei/course-state.json";
export const COURSE_FILE_LIMIT = 32 * 1024 * 1024;
export const COMMON_MATERIALS_DIRECTORY = "通用资料";
export const COMMON_NOTES_DIRECTORY = "通用笔记";
export const COURSE_MATERIALS_DIRECTORY = "文稿";
export const COURSE_NOTES_DIRECTORY = "笔记";

const supportedExtensions: Record<string, StudyItemKind> = {
  ".pdf": "pdf",
  ".html": "html",
  ".htm": "html",
  ".md": "markdown",
  ".markdown": "markdown",
  ".txt": "text",
  ".text": "text",
  ".png": "text",
  ".jpg": "text",
  ".jpeg": "text",
  ".webp": "text",
  ".gif": "text",
  ".heic": "text",
  ".tif": "text",
  ".tiff": "text",
  ".bmp": "text",
};

const unsupportedReaderExtensions = new Set([
  ".png", ".jpg", ".jpeg", ".webp", ".gif",
  ".heic", ".tif", ".tiff", ".bmp",
]);

interface PortableCourse {
  rootPath: string;
  manifestPath: string;
  statePath: string;
  courseID: string;
  state: SwiftJSONObject;
  digest: string;
}

interface CreatedCourseFile {
  absolutePath: string;
  relativePath: string;
  digest: string;
  parentDirectory: VerifiedDirectoryIdentity;
  dev: bigint;
  ino: bigint;
  size: bigint;
  mtimeNs: bigint;
}

export interface CourseLibraryOptions {
  rootPath: string;
  sessionsForCourse?: (courseID: string) => Promise<CourseDetail["sessions"]>;
  migrateLegacySessions?: (
    courseID: string,
    sessions: readonly SwiftJSONObject[],
    context: LegacySessionMigrationContext,
  ) => Promise<void>;
}

export interface LegacySessionMigrationContext {
  itemIDs: readonly string[];
  noteItemIDs: readonly string[];
  materialItemIDs: readonly string[];
  memoryIDs: readonly string[];
  relations: readonly {
    id: string;
    noteItemID: string;
    sourceItemID: string;
  }[];
}

export interface OpenCourseItem {
  payload: Omit<DocumentPayload, "documentGrantUrl">;
  absolutePath: string;
}

export class CourseLibrary {
  readonly rootPath: string;
  private readonly sessionsForCourse: NonNullable<CourseLibraryOptions["sessionsForCourse"]>;
  private readonly migrateLegacySessions: CourseLibraryOptions["migrateLegacySessions"];
  private queue: Promise<void> = Promise.resolve();

  constructor(options: CourseLibraryOptions | string) {
    this.rootPath = path.resolve(typeof options === "string" ? options : options.rootPath);
    this.sessionsForCourse = typeof options === "string" || !options.sessionsForCourse
      ? async () => []
      : options.sessionsForCourse;
    this.migrateLegacySessions = typeof options === "string"
      ? undefined
      : options.migrateLegacySessions;
  }

  async ensureLayout(): Promise<void> {
    await Promise.all([
      mkdir(this.rootPath, { recursive: true }),
      mkdir(path.join(this.rootPath, COMMON_MATERIALS_DIRECTORY), { recursive: true }),
      mkdir(path.join(this.rootPath, COMMON_NOTES_DIRECTORY), { recursive: true }),
    ]);
  }

  async listCourses(): Promise<CourseSummary[]> {
    await this.ensureLayout();
    const entries = await readdir(this.rootPath, { withFileTypes: true });
    assertNoWindowsNameCollisions(entries.filter((entry) => entry.isDirectory()).map((entry) => entry.name));
    const summaries = await Promise.all(
      entries
        .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
        .map(async (entry) => {
          try {
            const course = await this.loadCourseRoot(path.join(this.rootPath, entry.name));
            return summaryFromPortable(course);
          } catch {
            return null;
          }
        }),
    );
    const validSummaries = summaries
      .filter((summary): summary is CourseSummary => summary !== null);
    assertNoDuplicateCourseIDs(validSummaries);
    return validSummaries
      .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt) || left.title.localeCompare(right.title, "zh-Hans"));
  }

  async detail(courseID: string, selection?: {
    activeItemId?: string | null;
    activeNoteId?: string | null;
    activeSessionId?: string | null;
  }): Promise<CourseDetail> {
    return this.runExclusive(async () => {
      const course = await this.findCourse(courseID);
      const currentBytes = await readBounded(course.statePath, COURSE_FILE_LIMIT);
      if (sha256(currentBytes) !== course.digest) {
        throw new CourseLibraryError("portable-state-conflict");
      }
      await this.externalizeLegacySessions(course, currentBytes);
      const summary = summaryFromPortable(course);
      const items = await refreshedItemsFromPortable(course);
      const sessions = await this.sessionsForCourse(courseID);
      return {
        ...summary,
        items,
        sessions,
        activeItemId: selection?.activeItemId && items.some((item) => item.id === selection.activeItemId)
          ? selection.activeItemId
          : items.find((item) => !item.isNotebookNote || item.appearsInMaterials)?.id ?? null,
        activeNoteId: selection?.activeNoteId && items.some((item) => item.id === selection.activeNoteId && item.isNotebookNote)
          ? selection.activeNoteId
          : items.find((item) => item.isNotebookNote)?.id ?? null,
        activeSessionId: selection?.activeSessionId && sessions.some((session) => session.id === selection.activeSessionId)
          ? selection.activeSessionId
          : sessions[0]?.id ?? null,
      };
    });
  }

  /**
   * Make schema-v1 embedded Chat visible in the global session store without
   * requiring an unrelated course edit. The portable course remains v1 until
   * its next successful write, so a failed externalization never clears it.
   */
  async ensureLegacySessionsExternalized(courseID: string): Promise<void> {
    return this.runExclusive(async () => {
      const course = await this.findCourse(courseID);
      const currentBytes = await readBounded(course.statePath, COURSE_FILE_LIMIT);
      if (sha256(currentBytes) !== course.digest) {
        throw new CourseLibraryError("portable-state-conflict");
      }
      await this.externalizeLegacySessions(course, currentBytes);
    });
  }

  async createCourse(title: string, colorIndex = 0): Promise<CourseSummary> {
    return this.runExclusive(async () => {
      await this.ensureLayout();
      const cleanTitle = title.trim();
      if (!cleanTitle || cleanTitle.length > 120) throw new CourseLibraryError("invalid-title");
      const libraryDirectory = await verifiedExistingDirectory(this.rootPath);
      const requestedFolderName = safeFileName(cleanTitle, "新课程");
      const occupiedNames = new Set(
        (await readdir(libraryDirectory.absolutePath)).map(windowsCollisionKey),
      );
      let courseRoot: VerifiedDirectoryIdentity | null = null;
      while (!courseRoot) {
        const folderName = uniqueNameInSet(requestedFolderName, occupiedNames);
        try {
          courseRoot = await createDirectoryExclusiveVerified(
            path.join(libraryDirectory.absolutePath, folderName),
            libraryDirectory.absolutePath,
            libraryDirectory,
          );
        } catch (error) {
          if (!isAlreadyExistsError(error)) throw error;
          // Another CourseLibrary/Finder/iCloud instance won this exact name
          // after our directory scan. Never adopt it; select a fresh name.
          occupiedNames.add(windowsCollisionKey(folderName));
        }
      }

      const createdDirectories: VerifiedDirectoryIdentity[] = [courseRoot];
      const createdFiles: CreatedCourseFile[] = [];
      try {
        for (const childName of [
          COURSE_MATERIALS_DIRECTORY,
          COURSE_NOTES_DIRECTORY,
          ".weibei",
        ]) {
          createdDirectories.push(await createDirectoryExclusiveVerified(
            path.join(courseRoot.absolutePath, childName),
            courseRoot.absolutePath,
            courseRoot,
          ));
        }
        await assertCreatedCourseDirectories(createdDirectories);
        const metadataDirectory = createdDirectories.find((directory) =>
          path.basename(directory.absolutePath) === ".weibei");
        if (!metadataDirectory) {
          throw new CourseLibraryError("unsafe-course-root");
        }

        const courseID = randomUUID();
        const now = new Date();
        const manifestBytes = stringifySwiftJSON(
          { courseID, schemaVersion: 1 },
          { sortKeys: true },
        );
        const stateBytes = stringifySwiftJSON(
          emptyPortableState(courseID, cleanTitle, colorIndex, now),
          { sortKeys: true },
        );
        for (const [relativePath, bytes] of [
          [COURSE_MANIFEST_RELATIVE_PATH, manifestBytes],
          [COURSE_STATE_RELATIVE_PATH, stateBytes],
        ] as const) {
          await assertCreatedCourseDirectories(createdDirectories);
          const absolutePath = path.join(courseRoot.absolutePath, relativePath);
          const digest = await atomicCreateVerified(
            absolutePath,
            bytes,
            metadataDirectory,
          );
          const info = await lstat(absolutePath, { bigint: true });
          if (!info.isFile() || info.isSymbolicLink()) {
            throw new CourseLibraryError("unsafe-course-root");
          }
          createdFiles.push({
            absolutePath,
            relativePath,
            digest,
            parentDirectory: metadataDirectory,
            dev: info.dev,
            ino: info.ino,
            size: info.size,
            mtimeNs: info.mtimeNs,
          });
        }

        await assertCreatedCourseDirectories(createdDirectories);
        const portable = await this.loadCourseRoot(courseRoot.absolutePath);
        await assertCreatedCourseDirectories(createdDirectories);
        return summaryFromPortable(portable);
      } catch (error) {
        await rollbackExclusiveCourseCreation(createdDirectories, createdFiles);
        throw error;
      }
    });
  }

  async importFiles(courseID: string, sourcePaths: readonly string[]): Promise<StudyItem[]> {
    return this.runExclusive(async () => {
      if (sourcePaths.length === 0) return [];
      const course = await this.findCourse(courseID);
      const currentBytes = await readBounded(course.statePath, COURSE_FILE_LIMIT);
      if (sha256(currentBytes) !== course.digest) {
        throw new CourseLibraryError("portable-state-conflict");
      }
      requirePortableRevisionCanAdvance(course.state.revision);
      await this.externalizeLegacySessions(course, currentBytes);
      const existingItems = portableItemRecords(course.state);
      const imported: SwiftJSONObject[] = [];
      const createdFiles: CreatedCourseFile[] = [];
      const materialsDirectory = await verifiedCourseSubdirectory(
        course.rootPath,
        COURSE_MATERIALS_DIRECTORY,
      );
      const occupiedNames = new Set(
        (await readdir(materialsDirectory.absolutePath)).map(windowsCollisionKey),
      );
      try {
        for (const sourcePath of sourcePaths) {
          const source = path.resolve(sourcePath);
          const extension = path.extname(source).toLocaleLowerCase("en-US");
          const kind = supportedExtensions[extension];
          if (!kind) throw new CourseLibraryError("unsupported-file", path.basename(source));
          const before = await stableFileSnapshot(source);
          if (before.byteLength > COURSE_FILE_LIMIT) throw new CourseLibraryError("file-too-large", path.basename(source));
          const requestedName = safeFileName(path.basename(source), `未命名${extension}`);
          let copied: {
            name: string;
            relativePath: string;
            target: string;
            digest: string;
            targetStats: BigIntStats;
          } | null = null;
          while (!copied) {
            const name = uniqueNameInSet(requestedName, occupiedNames);
            const relativePath = `${COURSE_MATERIALS_DIRECTORY}/${name}`;
            const target = path.join(materialsDirectory.absolutePath, name);
            try {
              await assertVerifiedDirectory(materialsDirectory);
              const digest = await copyFileExclusiveVerified(
                source,
                target,
                materialsDirectory,
              );
              await assertVerifiedDirectory(materialsDirectory);
              const targetStats = await lstat(target, { bigint: true });
              if (!targetStats.isFile() || targetStats.isSymbolicLink()) {
                throw new CourseLibraryError("unsafe-item");
              }
              copied = { name, relativePath, target, digest, targetStats };
            } catch (error) {
              if (!isAlreadyExistsError(error)) throw error;
              // Finder/iCloud won the naming race. Preserve that file and pick
              // a new Windows-collision-safe name for this import.
              occupiedNames.add(windowsCollisionKey(name));
            }
          }
          const { name, relativePath, target, digest, targetStats } = copied;
          occupiedNames.add(windowsCollisionKey(name));
          createdFiles.push({
            absolutePath: target,
            relativePath,
            digest,
            parentDirectory: materialsDirectory,
            dev: targetStats.dev,
            ino: targetStats.ino,
            size: targetStats.size,
            mtimeNs: targetStats.mtimeNs,
          });
          const after = await stableFileSnapshot(source);
          if (before.digest !== after.digest || before.byteLength !== after.byteLength || before.mtimeNs !== after.mtimeNs) {
            throw new CourseLibraryError("source-changed", path.basename(source));
          }
          imported.push({
            itemID: `imported:${randomUUID().toLocaleLowerCase("en-US")}`,
            title: path.basename(name, path.extname(name)),
            kind,
            isNotebookNote: kind === "markdown",
            appearsInMaterials: true,
            courseRelativePath: relativePath,
            storage: { kind: "courseOwned" },
            contentRevision: 1,
            contentDigest: digest,
            fileByteCount: targetStats.size,
            fileModificationTimeNanoseconds: targetStats.mtimeNs,
            membershipCreatedAt: swiftReferenceSecondsFromDate(new Date()),
          });
        }
        await this.saveCourseState(course, [...existingItems, ...imported]);
        return itemsFromPortable(await this.loadCourseRoot(course.rootPath)).filter((item) =>
          imported.some((raw) => raw.itemID === item.id),
        );
      } catch (error) {
        await rollbackUnregisteredCourseFiles(course, createdFiles);
        throw error;
      }
    });
  }

  async createNote(courseID: string, title: string): Promise<StudyItem> {
    return this.runExclusive(async () => {
      const course = await this.findCourse(courseID);
      const currentBytes = await readBounded(course.statePath, COURSE_FILE_LIMIT);
      if (sha256(currentBytes) !== course.digest) {
        throw new CourseLibraryError("portable-state-conflict");
      }
      requirePortableRevisionCanAdvance(course.state.revision);
      await this.externalizeLegacySessions(course, currentBytes);
      const cleanTitle = title.trim();
      if (!cleanTitle || cleanTitle.length > 120) throw new CourseLibraryError("invalid-title");
      const notesDirectory = await verifiedCourseSubdirectory(
        course.rootPath,
        COURSE_NOTES_DIRECTORY,
      );
      const occupiedNames = new Set(
        (await readdir(notesDirectory.absolutePath)).map(windowsCollisionKey),
      );
      const requestedName = `${safeFileName(cleanTitle, "无题笔记")}.md`;
      const initial = `# ${cleanTitle}\n\n`;
      const createdFiles: CreatedCourseFile[] = [];
      try {
        let createdFile: {
          name: string;
          relativePath: string;
          target: string;
          digest: string;
          targetStats: BigIntStats;
        } | null = null;
        while (!createdFile) {
          const name = uniqueNameInSet(requestedName, occupiedNames);
          const relativePath = `${COURSE_NOTES_DIRECTORY}/${name}`;
          const target = path.join(notesDirectory.absolutePath, name);
          try {
            await assertVerifiedDirectory(notesDirectory);
            const digest = await atomicCreateVerified(
              target,
              initial,
              notesDirectory,
            );
            await assertVerifiedDirectory(notesDirectory);
            const targetStats = await lstat(target, { bigint: true });
            if (!targetStats.isFile() || targetStats.isSymbolicLink()) {
              throw new CourseLibraryError("unsafe-item");
            }
            createdFile = { name, relativePath, target, digest, targetStats };
          } catch (error) {
            if (!isAlreadyExistsError(error)) throw error;
            occupiedNames.add(windowsCollisionKey(name));
          }
        }
        const { relativePath, target, digest, targetStats } = createdFile;
        createdFiles.push({
          absolutePath: target,
          relativePath,
          digest,
          parentDirectory: notesDirectory,
          dev: targetStats.dev,
          ino: targetStats.ino,
          size: targetStats.size,
          mtimeNs: targetStats.mtimeNs,
        });
        const record: SwiftJSONObject = {
          itemID: `imported:${randomUUID().toLocaleLowerCase("en-US")}`,
          title: cleanTitle,
          kind: "markdown",
          isNotebookNote: true,
          appearsInMaterials: false,
          courseRelativePath: relativePath,
          storage: { kind: "courseOwned" },
          contentRevision: 1,
          contentDigest: digest,
          fileByteCount: targetStats.size,
          fileModificationTimeNanoseconds: targetStats.mtimeNs,
          membershipCreatedAt: swiftReferenceSecondsFromDate(new Date()),
        };
        await this.saveCourseState(course, [...portableItemRecords(course.state), record]);
        const created = itemsFromPortable(await this.loadCourseRoot(course.rootPath)).find((item) => item.id === record.itemID);
        if (!created) throw new CourseLibraryError("write-verification-failed");
        return created;
      } catch (error) {
        await rollbackUnregisteredCourseFiles(course, createdFiles);
        throw error;
      }
    });
  }

  async openItem(courseID: string, itemID: string): Promise<OpenCourseItem> {
    const course = await this.findCourse(courseID);
    const raw = portableItemRecords(course.state).find((entry) => entry.itemID === itemID);
    if (!raw) throw new CourseLibraryError("item-not-found");
    const relativePath = requiredString(raw.courseRelativePath, "courseRelativePath");
    const portablePath = validatePortableRelativePath(relativePath);
    if (unsupportedReaderExtensions.has(
      path.extname(portablePath).toLocaleLowerCase("en-US"),
    )) {
      throw new CourseLibraryError("unsupported-reader-item");
    }
    await assertNoSymlinkComponents(course.rootPath, portablePath);
    const absolutePath = await resolveExistingInside(course.rootPath, portablePath);
    const stats = await lstat(absolutePath);
    if (!stats.isFile() || stats.isSymbolicLink()) throw new CourseLibraryError("unsafe-item");
    if (stats.size > COURSE_FILE_LIMIT) throw new CourseLibraryError("file-too-large");
    const item = studyItemFromPortable(raw);
    const digest = await sha256File(absolutePath);
    const mediaType = mediaTypeFor(item.kind);
    const content = item.kind === "pdf" ? null : await readFile(absolutePath, "utf8");
    return {
      absolutePath,
      payload: { item, mediaType, content, digest },
    };
  }

  async resolveItemPath(courseID: string, itemID: string): Promise<string> {
    return (await this.openItem(courseID, itemID)).absolutePath;
  }

  private async findCourse(courseID: string): Promise<PortableCourse> {
    if (!isUUID(courseID)) throw new CourseLibraryError("course-not-found");
    await this.ensureLayout();
    const entries = await readdir(this.rootPath, { withFileTypes: true });
    const matches: PortableCourse[] = [];
    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith(".")) continue;
      try {
        const course = await this.loadCourseRoot(path.join(this.rootPath, entry.name));
        if (sameUUID(course.courseID, courseID)) matches.push(course);
      } catch {
        // A damaged sibling course must not block the requested course.
      }
    }
    if (matches.length > 1) {
      throw new CourseLibraryError("duplicate-course-id", courseID);
    }
    if (matches[0]) return matches[0];
    throw new CourseLibraryError("course-not-found");
  }

  private async loadCourseRoot(candidateRoot: string): Promise<PortableCourse> {
    const [canonicalLibrary, rootPath] = await Promise.all([realpath(this.rootPath), realpath(candidateRoot)]);
    const relative = path.relative(canonicalLibrary, rootPath);
    if (!relative || path.isAbsolute(relative) || relative.startsWith(`..${path.sep}`) || relative === "..") {
      throw new CourseLibraryError("unsafe-course-root");
    }
    await recoverInterruptedCourseState(rootPath);
    await Promise.all([
      assertNoSymlinkComponents(rootPath, COURSE_MANIFEST_RELATIVE_PATH),
      assertNoSymlinkComponents(rootPath, COURSE_STATE_RELATIVE_PATH),
    ]);
    const [manifestPath, statePath] = await Promise.all([
      realpath(path.join(rootPath, COURSE_MANIFEST_RELATIVE_PATH)),
      realpath(path.join(rootPath, COURSE_STATE_RELATIVE_PATH)),
    ]);
    assertInside(rootPath, manifestPath);
    assertInside(rootPath, statePath);
    const [manifestBytes, stateBytes] = await Promise.all([
      readBounded(manifestPath, 1024 * 1024),
      readBounded(statePath, COURSE_FILE_LIMIT),
    ]);
    const manifest = asObject(parseSwiftJSON(manifestBytes.toString("utf8")));
    const state = asObject(parseSwiftJSON(stateBytes.toString("utf8")));
    const courseID = requiredString(manifest.courseID, "courseID");
    const stateCourseID = requiredString(state.courseID, "state.courseID");
    if (
      !isUUID(courseID)
      || !isUUID(stateCourseID)
      || manifest.schemaVersion !== 1
      || !sameUUID(stateCourseID, courseID)
      || ![1, 2].includes(numberValue(state.schemaVersion))
    ) {
      throw new CourseLibraryError("invalid-portable-state");
    }
    if (!Array.isArray(state.items) || !asObject(state.metadata)) throw new CourseLibraryError("invalid-portable-state");
    validatePortableItems(state.items, rootPath);
    return { rootPath, manifestPath, statePath, courseID, state, digest: sha256(stateBytes) };
  }

  private async saveCourseState(course: PortableCourse, items: SwiftJSONObject[]): Promise<void> {
    const metadataDirectory = await verifiedCourseSubdirectory(course.rootPath, ".weibei");
    const statePath = await verifiedCourseFile(
      course.rootPath,
      COURSE_STATE_RELATIVE_PATH,
      metadataDirectory,
    );
    if (!sameFilesystemPath(statePath, course.statePath)) {
      throw new CourseLibraryError("portable-state-conflict");
    }
    const currentBytes = await readBounded(statePath, COURSE_FILE_LIMIT);
    if (sha256(currentBytes) !== course.digest) throw new CourseLibraryError("portable-state-conflict");
    const current = asObject(parseSwiftJSON(currentBytes.toString("utf8")));
    const currentRevision = requirePortableRevisionCanAdvance(current.revision);
    await this.externalizeLegacySessions(course, currentBytes, current);
    await assertVerifiedDirectory(metadataDirectory);
    const beforeCommit = await readBounded(statePath, COURSE_FILE_LIMIT);
    if (!beforeCommit.equals(currentBytes)) {
      throw new CourseLibraryError("portable-state-conflict");
    }
    const now = new Date();
    const next: SwiftJSONObject = {
      ...current,
      schemaVersion: 2,
      revision: currentRevision + 1n,
      savedAt: swiftReferenceSecondsFromDate(now),
      metadata: { ...asObject(current.metadata), updatedAt: swiftReferenceSecondsFromDate(now) },
      items,
      studySessions: [],
    };
    const serialized = stringifySwiftJSON(next, { sortKeys: true });
    if (Buffer.byteLength(serialized) > COURSE_FILE_LIMIT) throw new CourseLibraryError("file-too-large");
    await assertVerifiedDirectory(metadataDirectory);
    try {
      await atomicReplaceVerified(
        statePath,
        currentBytes,
        serialized,
        metadataDirectory,
      );
    } catch (error) {
      if (error instanceof FileWriteConflictError) {
        throw new CourseLibraryError("portable-state-conflict");
      }
      throw error;
    }
    await assertVerifiedDirectory(metadataDirectory);
    const reread = await readFile(statePath);
    if (sha256(reread) !== sha256(serialized)) throw new CourseLibraryError("write-verification-failed");
  }

  private async externalizeLegacySessions(
    course: PortableCourse,
    currentBytes: Buffer,
    parsed?: SwiftJSONObject,
  ): Promise<void> {
    const current = parsed ?? asObject(parseSwiftJSON(currentBytes.toString("utf8")));
    const schemaVersion = numberValue(current.schemaVersion);
    const embeddedSessions = embeddedSessionRecords(current);
    if (schemaVersion === 2) {
      if (embeddedSessions.length > 0) {
        throw new CourseLibraryError("invalid-portable-state");
      }
      return;
    }
    const migrationContext = legacySessionMigrationContext(
      current,
      course.courseID,
    );
    if (embeddedSessions.length === 0) return;
    if (!this.migrateLegacySessions) {
      throw new CourseLibraryError("legacy-session-migration-required");
    }
    // Session bodies must be durably externalized before a later course write
    // can upgrade to v2. Recheck exact bytes after the async workspace commit:
    // an iCloud/Finder/other-process edit must never be overwritten by stale
    // state captured before migration.
    await this.migrateLegacySessions(
      course.courseID,
      embeddedSessions,
      migrationContext,
    );
    const afterMigration = await readBounded(course.statePath, COURSE_FILE_LIMIT);
    if (!afterMigration.equals(currentBytes)) {
      throw new CourseLibraryError("portable-state-conflict");
    }
  }

  private async runExclusive<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.queue.then(operation, operation);
    this.queue = result.then(() => undefined, () => undefined);
    return result;
  }
}

export class CourseLibraryError extends Error {
  constructor(readonly code: string, detail?: string) {
    super(detail ? `${code}: ${detail}` : code);
    this.name = "CourseLibraryError";
  }
}

function emptyPortableState(courseID: string, title: string, colorIndex: number, now: Date): SwiftJSONObject {
  return {
    courseID,
    schemaVersion: 2,
    revision: 0,
    savedAt: swiftReferenceSecondsFromDate(now),
    metadata: {
      title,
      colorIndex,
      createdAt: swiftReferenceSecondsFromDate(now),
      updatedAt: swiftReferenceSecondsFromDate(now),
    },
    items: [],
    studySessions: [],
    learningMemoryState: null,
    courseKnowledgeProfile: null,
    noteSourceLinks: [],
    studyLocationsByItemID: {},
    resumePoint: null,
    pendingNoteDrafts: [],
  };
}

function summaryFromPortable(course: PortableCourse): CourseSummary {
  const metadata = asObject(course.state.metadata);
  const items = portableItemRecords(course.state);
  return {
    id: course.courseID,
    title: requiredString(metadata.title, "metadata.title"),
    colorIndex: Math.max(0, Math.trunc(numberValue(metadata.colorIndex))),
    rootPath: course.rootPath,
    createdAt: dateValue(metadata.createdAt).toISOString(),
    updatedAt: dateValue(metadata.updatedAt).toISOString(),
    itemCount: items.length,
  };
}

function itemsFromPortable(course: PortableCourse): StudyItem[] {
  return portableItemRecords(course.state).map(studyItemFromPortable);
}

async function refreshedItemsFromPortable(course: PortableCourse): Promise<StudyItem[]> {
  return Promise.all(portableItemRecords(course.state).map(async (raw) => {
    const item = studyItemFromPortable(raw);
    try {
      const relativePath = validatePortableRelativePath(requiredString(raw.courseRelativePath, "item.courseRelativePath"));
      if (unsupportedReaderExtensions.has(
        path.extname(relativePath).toLocaleLowerCase("en-US"),
      )) {
        return { ...item, unavailable: true, contentDigest: null };
      }
      await assertNoSymlinkComponents(course.rootPath, relativePath);
      const absolutePath = await resolveExistingInside(course.rootPath, relativePath);
      const stats = await lstat(absolutePath, { bigint: true });
      if (!stats.isFile() || stats.isSymbolicLink() || stats.size > COURSE_FILE_LIMIT) {
        return { ...item, unavailable: true, contentDigest: null };
      }
      return { ...item, unavailable: false, contentDigest: await sha256File(absolutePath) };
    } catch {
      return { ...item, unavailable: true, contentDigest: null };
    }
  }));
}

function portableItemRecords(state: SwiftJSONObject): SwiftJSONObject[] {
  if (!Array.isArray(state.items)) throw new CourseLibraryError("invalid-portable-state");
  return state.items.map(asObject);
}

function embeddedSessionRecords(state: SwiftJSONObject): SwiftJSONObject[] {
  if (state.studySessions === undefined) return [];
  if (!Array.isArray(state.studySessions)) {
    throw new CourseLibraryError("invalid-portable-state");
  }
  return state.studySessions.map(asObject);
}

function legacySessionMigrationContext(
  state: SwiftJSONObject,
  courseID: string,
): LegacySessionMigrationContext {
  requireIntegerRange(state.revision, 0n, 18_446_744_073_709_551_615n);
  validateSwiftDate(state.savedAt);
  if (
    !Array.isArray(state.items)
    || !Array.isArray(state.studySessions)
    || !Array.isArray(state.noteSourceLinks)
    || !Array.isArray(state.pendingNoteDrafts)
    || !state.studyLocationsByItemID
    || typeof state.studyLocationsByItemID !== "object"
    || Array.isArray(state.studyLocationsByItemID)
  ) {
    throw new CourseLibraryError("invalid-portable-state");
  }
  const metadata = asObject(state.metadata);
  if (!requiredString(metadata.title, "metadata.title").trim()) {
    throw new CourseLibraryError("invalid-portable-state");
  }
  requireIntegerRange(
    metadata.colorIndex,
    -9_223_372_036_854_775_808n,
    9_223_372_036_854_775_807n,
  );
  validateSwiftDate(metadata.createdAt);
  validateSwiftDate(metadata.updatedAt);
  for (const draftValue of state.pendingNoteDrafts) {
    const draft = asObject(draftValue);
    requiredString(draft.itemID, "pendingNoteDraft.itemID");
    requireStringType(draft.markdown);
    if (
      draft.baselineContentDigest !== undefined
      && draft.baselineContentDigest !== null
      && typeof draft.baselineContentDigest !== "string"
    ) {
      throw new CourseLibraryError("invalid-portable-state");
    }
  }
  for (const locationValue of Object.values(
    state.studyLocationsByItemID as SwiftJSONObject,
  )) {
    validateStudyLocationCodableShape(asObject(locationValue));
  }
  const items = portableItemRecords(state);
  const itemIDs = items.map((item) => requiredString(item.itemID, "item.itemID"));
  const noteItemIDs = items
    .filter((item) => item.isNotebookNote === true)
    .map((item) => requiredString(item.itemID, "item.itemID"));
  const materialItemIDs = items
    .filter((item) => typeof item.appearsInMaterials === "boolean"
      ? item.appearsInMaterials
      : item.isNotebookNote !== true)
    .map((item) => requiredString(item.itemID, "item.itemID"));
  const noteIDs = new Set(noteItemIDs);
  const materialIDs = new Set(materialItemIDs);

  const rawRelations = state.noteSourceLinks;
  if (
    rawRelations !== undefined
    && rawRelations !== null
    && !Array.isArray(rawRelations)
  ) {
    throw new CourseLibraryError("invalid-portable-state");
  }
  const seenRelationIDs = new Set<string>();
  const relations: LegacySessionMigrationContext["relations"][number][] = [];
  const normalizedRelations: SwiftJSONObject[] = [];
  for (const relationValue of Array.isArray(rawRelations) ? rawRelations : []) {
    const relation = asObject(relationValue);
    const id = requireStringType(relation.id);
    if (!isUUID(id)) throw new CourseLibraryError("invalid-portable-state");
    validateSwiftDate(relation.createdAt);
    const noteItemID = requireStringType(relation.noteItemID);
    const sourceItemID = requireStringType(relation.sourceItemID);
    if (
      !noteIDs.has(noteItemID)
      || !materialIDs.has(sourceItemID)
      || noteItemID === sourceItemID
    ) {
      continue;
    }
    const key = id.toLocaleLowerCase("en-US");
    if (seenRelationIDs.has(key)) {
      throw new CourseLibraryError("invalid-portable-state");
    }
    seenRelationIDs.add(key);
    normalizedRelations.push(relation);
    relations.push({ id, noteItemID, sourceItemID });
  }

  const messageIDsBySessionID = new Map<string, Set<string>>();
  const normalizedSessionMessages: Array<{
    session: SwiftJSONObject;
    messages: SwiftJSONValue[];
  }> = [];
  for (const session of embeddedSessionRecords(state)) {
    const sessionID = requiredString(session.id, "studySession.id");
    if (!isUUID(sessionID)) throw new CourseLibraryError("invalid-portable-state");
    const sessionKey = sessionID.toLocaleLowerCase("en-US");
    if (messageIDsBySessionID.has(sessionKey)) {
      throw new CourseLibraryError("invalid-portable-state");
    }
    const messages = session.messages === undefined || session.messages === null
      ? []
      : Array.isArray(session.messages)
        ? session.messages
        : null;
    if (!messages) throw new CourseLibraryError("invalid-portable-state");
    normalizedSessionMessages.push({ session, messages });
    const messageIDs = new Set<string>();
    for (const messageValue of messages) {
      const messageID = requiredString(asObject(messageValue).id, "message.id");
      if (!isUUID(messageID)) throw new CourseLibraryError("invalid-portable-state");
      const messageKey = messageID.toLocaleLowerCase("en-US");
      if (messageIDs.has(messageKey)) {
        throw new CourseLibraryError("invalid-portable-state");
      }
      messageIDs.add(messageKey);
    }
    messageIDsBySessionID.set(sessionKey, messageIDs);
  }

  const rawMemoryState = state.learningMemoryState;
  let memoryIDs: string[] = [];
  if (rawMemoryState !== undefined && rawMemoryState !== null) {
    const memoryState = asObject(rawMemoryState);
    if (!Array.isArray(memoryState.entries)) {
      throw new CourseLibraryError("invalid-portable-state");
    }
    requireIntegerRange(
      memoryState.revision,
      0n,
      18_446_744_073_709_551_615n,
    );
    const scope = asObject(memoryState.scope);
    const courseScope = asObject(scope.course);
    if (
      Object.keys(scope).length !== 1
      || typeof courseScope._0 !== "string"
      || !sameUUID(courseScope._0, courseID)
    ) {
      throw new CourseLibraryError("invalid-portable-state");
    }
    const seenMemoryIDs = new Set<string>();
    memoryIDs = memoryState.entries.map((entryValue) => {
      const entry = asObject(entryValue);
      validateLearningMemoryEntryCodableShape(entry);
      const id = requiredString(entry.id, "learningMemoryState.entry.id");
      if (!isUUID(id)) throw new CourseLibraryError("invalid-portable-state");
      const key = id.toLocaleLowerCase("en-US");
      if (seenMemoryIDs.has(key)) {
        throw new CourseLibraryError("invalid-portable-state");
      }
      seenMemoryIDs.add(key);
      validatePortableMemoryProvenance(entry, messageIDsBySessionID);
      if (entry.revisions !== undefined && entry.revisions !== null) {
        if (!Array.isArray(entry.revisions)) {
          throw new CourseLibraryError("invalid-portable-state");
        }
        for (const revision of entry.revisions) {
          const revisionRecord = asObject(revision);
          validateLearningMemoryRevisionCodableShape(revisionRecord);
          validatePortableMemoryProvenance(
            revisionRecord,
            messageIDsBySessionID,
          );
        }
      }
      return id;
    });
  }

  let normalizedResumePoint = state.resumePoint;
  if (state.resumePoint !== undefined && state.resumePoint !== null) {
    const resumePoint = asObject(state.resumePoint);
    validateCourseResumePointCodableShape(resumePoint);
    if (!sameUUID(requireStringType(resumePoint.courseID), courseID)) {
      normalizedResumePoint = null;
    } else {
      const normalized = { ...resumePoint };
      if (
        normalized.materialLocation !== undefined
        && normalized.materialLocation !== null
        && !materialIDs.has(requireStringType(
          asObject(normalized.materialLocation).itemID,
        ))
      ) {
        normalized.materialLocation = null;
      }
      if (
        typeof normalized.noteItemID === "string"
        && !noteIDs.has(normalized.noteItemID)
      ) {
        normalized.noteItemID = null;
      }
      normalizedResumePoint = normalized.materialLocation == null
        && normalized.chatID == null
        && normalized.noteItemID == null
        ? null
        : normalized;
      if (
        normalizedResumePoint
        && typeof normalizedResumePoint === "object"
        && !Array.isArray(normalizedResumePoint)
        && typeof normalizedResumePoint.chatID === "string"
        && !messageIDsBySessionID.has(
          normalizedResumePoint.chatID.toLocaleLowerCase("en-US"),
        )
      ) {
        normalizedResumePoint = null;
      }
    }
  }

  let normalizedCourseKnowledgeProfile = state.courseKnowledgeProfile;
  if (
    state.courseKnowledgeProfile !== undefined
    && state.courseKnowledgeProfile !== null
  ) {
    const profile = asObject(state.courseKnowledgeProfile);
    if (
      typeof profile.courseID !== "string"
      || !sameUUID(profile.courseID, courseID)
    ) {
      throw new CourseLibraryError("invalid-portable-state");
    }
    requireIntegerRange(
      profile.revision,
      0n,
      18_446_744_073_709_551_615n,
    );
    if (profile.updatedAt !== undefined && profile.updatedAt !== null) {
      validateSwiftDate(profile.updatedAt);
    }
    const entries = decodeCourseKnowledgeProfileEntriesLikeSwift(profile.entries);
    const entryIDs = new Set<string>();
    for (const entryValue of entries) {
      const entry = asObject(entryValue);
      const id = requiredString(entry.id, "courseKnowledgeProfile.entry.id");
      if (!isUUID(id) || !requiredString(
        entry.text,
        "courseKnowledgeProfile.entry.text",
      ).trim()) {
        throw new CourseLibraryError("invalid-portable-state");
      }
      const key = id.toLocaleLowerCase("en-US");
      if (entryIDs.has(key)) throw new CourseLibraryError("invalid-portable-state");
      entryIDs.add(key);
    }
    normalizedCourseKnowledgeProfile = {
      ...profile,
      overview: typeof profile.overview === "string" ? profile.overview : "",
      entries,
    };
  }

  state.noteSourceLinks = normalizedRelations;
  state.resumePoint = normalizedResumePoint;
  state.courseKnowledgeProfile = normalizedCourseKnowledgeProfile;
  for (const { session, messages } of normalizedSessionMessages) {
    session.messages = messages;
  }
  return { itemIDs, noteItemIDs, materialItemIDs, memoryIDs, relations };
}

const learningMemoryKinds = new Set([
  "goal",
  "progress",
  "understood",
  "confusion",
  "nextStep",
  "summary",
  "preference",
]);
const learningMemoryOrigins = new Set([
  "userStatement",
  "agentInference",
  "observed",
]);
const learningMemoryStatuses = new Set(["active", "resolved"]);
const learningMemoryRevisionActors = new Set(["user", "agent", "migration"]);
const courseKnowledgeProfileEntryKinds = new Set(["concept"]);
const courseKnowledgeProfileSourceRoles = new Set(["material", "note"]);
const swiftIntMinimum = -9_223_372_036_854_775_808n;
const swiftIntMaximum = 9_223_372_036_854_775_807n;
const swiftUIntMaximum = 18_446_744_073_709_551_615n;

function validateStudyLocationCodableShape(value: SwiftJSONObject): void {
  requireStringType(value.itemID);
  requireStringType(value.itemTitle);
  validateOptionalStringType(value.locationID);
  validateOptionalStringType(value.locationTitle);
  if (value.pageIndex !== undefined && value.pageIndex !== null) {
    requireIntegerRange(value.pageIndex, swiftIntMinimum, swiftIntMaximum);
  }
  validateSwiftDate(value.lastStudiedAt);
  requireIntegerRange(value.visitCount, swiftIntMinimum, swiftIntMaximum);
}

function validateCourseResumePointCodableShape(value: SwiftJSONObject): void {
  if (typeof value.courseID !== "string" || !isUUID(value.courseID)) {
    throw new CourseLibraryError("invalid-portable-state");
  }
  if (value.materialLocation !== undefined && value.materialLocation !== null) {
    validateStudyLocationCodableShape(asObject(value.materialLocation));
  }
  validateOptionalUUID(value.chatID);
  validateOptionalStringType(value.noteItemID);
  validateSwiftDate(value.savedAt);
}

function validateLearningMemoryEntryCodableShape(value: SwiftJSONObject): void {
  validateRequiredUUID(value.id);
  validateStringEnum(value.kind, learningMemoryKinds);
  requireStringType(value.text);
  requireStringType(value.evidence);
  validateStringEnum(value.origin, learningMemoryOrigins);
  validateStringEnum(value.status, learningMemoryStatuses);
  validateOptionalUUID(value.sessionID);
  validateOptionalUUID(value.messageID);
  if (value.resolvedAt !== undefined && value.resolvedAt !== null) {
    validateSwiftDate(value.resolvedAt);
  }
  validateOptionalStringType(value.resolutionEvidence);
  validateSwiftDate(value.createdAt);
  validateSwiftDate(value.updatedAt);
  if (
    value.revisions !== undefined
    && value.revisions !== null
    && !Array.isArray(value.revisions)
  ) {
    throw new CourseLibraryError("invalid-portable-state");
  }
}

function validateLearningMemoryRevisionCodableShape(value: SwiftJSONObject): void {
  validateRequiredUUID(value.id);
  requireIntegerRange(value.revision, 0n, swiftUIntMaximum);
  validateStringEnum(value.kind, learningMemoryKinds);
  requireStringType(value.text);
  requireStringType(value.evidence);
  validateStringEnum(value.origin, learningMemoryOrigins);
  validateStringEnum(value.status, learningMemoryStatuses);
  validateOptionalUUID(value.sessionID);
  validateOptionalUUID(value.messageID);
  validateOptionalStringType(value.resolutionEvidence);
  validateStringEnum(value.actor, learningMemoryRevisionActors);
  validateSwiftDate(value.recordedAt);
}

function decodeCourseKnowledgeProfileEntriesLikeSwift(
  value: SwiftJSONValue | undefined,
): SwiftJSONObject[] {
  if (!Array.isArray(value)) return [];
  try {
    return value.map((entryValue) => {
      const entry = asObject(entryValue);
      validateRequiredUUID(entry.id);
      validateStringEnum(entry.kind, courseKnowledgeProfileEntryKinds);
      requireStringType(entry.text);
      validateSwiftDate(entry.createdAt);
      validateSwiftDate(entry.updatedAt);
      return {
        ...entry,
        sources: decodeCourseKnowledgeProfileSourcesLikeSwift(entry.sources),
      };
    });
  } catch (error) {
    // CourseKnowledgeProfile decodes the entire entries array with `try?`.
    // Preserve fail-closed handling for dates JavaScript cannot represent.
    if (!(error instanceof CourseLibraryError)) throw error;
    return [];
  }
}

function decodeCourseKnowledgeProfileSourcesLikeSwift(
  value: SwiftJSONValue | undefined,
): SwiftJSONObject[] {
  if (!Array.isArray(value)) return [];
  try {
    return value.map((sourceValue) => {
      const source = asObject(sourceValue);
      requireStringType(source.itemID);
      validateStringEnum(source.role, courseKnowledgeProfileSourceRoles);
      validateOptionalStringType(source.location);
      requireStringType(source.sourceRevision);
      return source;
    });
  } catch (error) {
    // CourseKnowledgeProfileEntry gives its compatibility-only sources field
    // an independent lossy decode boundary.
    if (!(error instanceof CourseLibraryError)) throw error;
    return [];
  }
}

function requireStringType(value: unknown): string {
  if (typeof value !== "string") {
    throw new CourseLibraryError("invalid-portable-state");
  }
  return value;
}

function validateOptionalStringType(value: unknown): void {
  if (value !== undefined && value !== null && typeof value !== "string") {
    throw new CourseLibraryError("invalid-portable-state");
  }
}

function validateRequiredUUID(value: unknown): void {
  if (typeof value !== "string" || !isUUID(value)) {
    throw new CourseLibraryError("invalid-portable-state");
  }
}

function validateOptionalUUID(value: unknown): void {
  if (
    value !== undefined
    && value !== null
    && (typeof value !== "string" || !isUUID(value))
  ) {
    throw new CourseLibraryError("invalid-portable-state");
  }
}

function validateStringEnum(value: unknown, allowed: ReadonlySet<string>): void {
  if (typeof value !== "string" || !allowed.has(value)) {
    throw new CourseLibraryError("invalid-portable-state");
  }
}

function validatePortableMemoryProvenance(
  value: SwiftJSONObject,
  messageIDsBySessionID: ReadonlyMap<string, ReadonlySet<string>>,
): void {
  const rawSessionID = value.sessionID;
  const rawMessageID = value.messageID;
  if (rawSessionID === undefined || rawSessionID === null) {
    if (rawMessageID !== undefined && rawMessageID !== null) {
      throw new CourseLibraryError("invalid-portable-state");
    }
    return;
  }
  if (typeof rawSessionID !== "string" || !isUUID(rawSessionID)) {
    throw new CourseLibraryError("invalid-portable-state");
  }
  const messageIDs = messageIDsBySessionID.get(
    rawSessionID.toLocaleLowerCase("en-US"),
  );
  if (!messageIDs) throw new CourseLibraryError("invalid-portable-state");
  if (rawMessageID === undefined || rawMessageID === null) return;
  if (
    typeof rawMessageID !== "string"
    || !isUUID(rawMessageID)
    || !messageIDs.has(rawMessageID.toLocaleLowerCase("en-US"))
  ) {
    throw new CourseLibraryError("invalid-portable-state");
  }
}

function studyItemFromPortable(raw: SwiftJSONObject): StudyItem {
  const relativePath = requiredString(raw.courseRelativePath, "item.courseRelativePath");
  const kind = requiredString(raw.kind, "item.kind") as StudyItemKind;
  if (!Object.values(supportedExtensions).includes(kind)) throw new CourseLibraryError("invalid-portable-state");
  const item: StudyItem = {
    id: requiredString(raw.itemID, "item.itemID"),
    title: requiredString(raw.title, "item.title"),
    subtitle: path.basename(relativePath),
    kind,
    isNotebookNote: raw.isNotebookNote === true,
    appearsInMaterials: typeof raw.appearsInMaterials === "boolean" ? raw.appearsInMaterials : raw.isNotebookNote !== true,
    relativePath,
    contentRevision: safeNumber(raw.contentRevision),
    contentDigest: typeof raw.contentDigest === "string" ? raw.contentDigest : null,
    unavailable: false,
  };
  return item;
}

function validatePortableItems(values: SwiftJSONValue[], rootPath: string): void {
  const ids = new Set<string>();
  const paths = new Set<string>();
  const collisionKeys = new Set<string>();
  for (const value of values) {
    const item = asObject(value);
    const id = requiredString(item.itemID, "itemID");
    if (
      typeof item.title !== "string"
      || typeof item.isNotebookNote !== "boolean"
      || (item.appearsInMaterials !== undefined
        && item.appearsInMaterials !== null
        && typeof item.appearsInMaterials !== "boolean")
    ) {
      throw new CourseLibraryError("invalid-portable-state");
    }
    requireIntegerRange(item.contentRevision, 0n, 18_446_744_073_709_551_615n);
    if (item.contentDigest !== undefined && item.contentDigest !== null
      && typeof item.contentDigest !== "string") {
      throw new CourseLibraryError("invalid-portable-state");
    }
    if (item.fileByteCount !== undefined && item.fileByteCount !== null) {
      requireIntegerRange(item.fileByteCount, 0n, 18_446_744_073_709_551_615n);
    }
    if (
      item.fileModificationTimeNanoseconds !== undefined
      && item.fileModificationTimeNanoseconds !== null
    ) {
      requireIntegerRange(
        item.fileModificationTimeNanoseconds,
        -9_223_372_036_854_775_808n,
        9_223_372_036_854_775_807n,
      );
    }
    validateSwiftDate(item.membershipCreatedAt);
    const relativePath = validatePortableRelativePath(requiredString(item.courseRelativePath, "courseRelativePath"));
    if (ids.has(id)) throw new CourseLibraryError("duplicate-item-id");
    // Swift normalizes first-path-wins before validating Chat references. This
    // reader keeps raw forward fields, so accepting the duplicate here would
    // incorrectly authorize the discarded item's ID during v1 migration.
    if (paths.has(relativePath)) throw new CourseLibraryError("duplicate-item-path");
    const collision = windowsCollisionKey(relativePath);
    if (collisionKeys.has(collision)) throw new CourseLibraryError("windows-path-collision", relativePath);
    const first = relativePath.split("/")[0];
    if (first !== COURSE_MATERIALS_DIRECTORY && first !== COURSE_NOTES_DIRECTORY) throw new CourseLibraryError("invalid-item-role");
    const kind = supportedExtensions[path.extname(relativePath).toLocaleLowerCase("en-US")];
    if (!kind || item.kind !== kind) throw new CourseLibraryError("invalid-item-kind");
    const pathDefinesNotebookNote = first === COURSE_NOTES_DIRECTORY && kind === "markdown";
    if (item.isNotebookNote === true) {
      if (!pathDefinesNotebookNote && !(first === COURSE_MATERIALS_DIRECTORY && kind === "markdown")) {
        throw new CourseLibraryError("invalid-note-kind");
      }
    } else if (pathDefinesNotebookNote) {
      throw new CourseLibraryError("invalid-note-kind");
    }
    const storage = asObject(item.storage);
    if (storage.kind === "sharedReference") {
      const sharedPath = requiredString(
        storage.sharedRelativePath,
        "storage.sharedRelativePath",
      );
      const expectedDigest = requiredString(
        storage.expectedContentDigest,
        "storage.expectedContentDigest",
      );
      if (
        !isStrictCommonPath(sharedPath, item.isNotebookNote)
        || !/^[0-9a-f]{64}$/u.test(expectedDigest)
        || item.contentDigest !== expectedDigest
      ) {
        throw new CourseLibraryError("invalid-item-storage");
      }
    } else if (storage.kind !== "courseOwned") {
      throw new CourseLibraryError("invalid-item-storage");
    }
    ids.add(id); paths.add(relativePath); collisionKeys.add(collision);
    void rootPath;
  }
}

function isStrictCommonPath(value: string, isNotebookNote: boolean): boolean {
  let portable: string;
  try {
    portable = validatePortableRelativePath(value);
  } catch {
    return false;
  }
  const components = portable.split("/");
  if (components.length !== 2 || components[1].startsWith(".")) return false;
  const kind = supportedExtensions[
    path.extname(components[1]).toLocaleLowerCase("en-US")
  ];
  if (isNotebookNote) {
    return (components[0] === COMMON_NOTES_DIRECTORY
      || components[0] === COMMON_MATERIALS_DIRECTORY)
      && kind === "markdown";
  }
  return (components[0] === COMMON_MATERIALS_DIRECTORY
    || components[0] === "共享文稿")
    && kind !== undefined;
}

async function stableFileSnapshot(filePath: string) {
  const info = await lstat(filePath, { bigint: true });
  if (!info.isFile() || info.isSymbolicLink()) throw new CourseLibraryError("not-regular-file");
  const digest = await sha256File(filePath);
  const confirmed = await lstat(filePath, { bigint: true });
  if (
    !confirmed.isFile()
    || confirmed.isSymbolicLink()
    || info.dev !== confirmed.dev
    || info.ino !== confirmed.ino
    || info.size !== confirmed.size
    || info.mtimeNs !== confirmed.mtimeNs
  ) throw new CourseLibraryError("source-changed");
  return { digest, byteLength: Number(info.size), mtimeNs: info.mtimeNs };
}

async function assertNoSymlinkComponents(rootPath: string, relativePath: string): Promise<void> {
  let current = rootPath;
  const components = relativePath.split("/");
  for (let index = 0; index < components.length; index += 1) {
    current = path.join(current, components[index]);
    const info = await lstat(current);
    if (info.isSymbolicLink()) throw new CourseLibraryError("unsafe-item");
    if (index < components.length - 1 && !info.isDirectory()) {
      throw new CourseLibraryError("unsafe-item");
    }
  }
}

async function verifiedCourseSubdirectory(
  courseRoot: string,
  relativeDirectory: string,
): Promise<VerifiedDirectoryIdentity> {
  await assertNoSymlinkComponents(courseRoot, relativeDirectory);
  const [canonicalRoot, canonicalDirectory] = await Promise.all([
    realpath(courseRoot),
    realpath(path.join(courseRoot, relativeDirectory)),
  ]);
  assertInside(canonicalRoot, canonicalDirectory);
  if (!sameFilesystemPath(path.dirname(canonicalDirectory), canonicalRoot)) {
    throw new CourseLibraryError("unsafe-course-root");
  }
  const info = await lstat(canonicalDirectory, { bigint: true });
  if (!info.isDirectory() || info.isSymbolicLink()) {
    throw new CourseLibraryError("unsafe-course-root");
  }
  const identity = {
    absolutePath: canonicalDirectory,
    dev: info.dev,
    ino: info.ino,
  };
  await assertVerifiedDirectory(identity);
  return identity;
}

async function verifiedExistingDirectory(
  directoryPath: string,
): Promise<VerifiedDirectoryIdentity> {
  const canonicalPath = await realpath(directoryPath);
  const info = await lstat(canonicalPath, { bigint: true });
  if (!info.isDirectory() || info.isSymbolicLink()) {
    throw new CourseLibraryError("unsafe-course-root");
  }
  const identity = {
    absolutePath: canonicalPath,
    dev: info.dev,
    ino: info.ino,
  };
  await assertVerifiedDirectory(identity);
  return identity;
}

async function verifiedCourseFile(
  courseRoot: string,
  relativePath: string,
  parentDirectory: VerifiedDirectoryIdentity,
): Promise<string> {
  await assertVerifiedDirectory(parentDirectory);
  await assertNoSymlinkComponents(courseRoot, relativePath);
  const canonicalPath = await realpath(path.join(courseRoot, relativePath));
  assertInside(await realpath(courseRoot), canonicalPath);
  if (!sameFilesystemPath(path.dirname(canonicalPath), parentDirectory.absolutePath)) {
    throw new CourseLibraryError("unsafe-course-root");
  }
  const info = await lstat(canonicalPath);
  if (!info.isFile() || info.isSymbolicLink()) {
    throw new CourseLibraryError("unsafe-or-large-file");
  }
  await assertVerifiedDirectory(parentDirectory);
  return canonicalPath;
}

async function assertVerifiedDirectory(
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
    throw new CourseLibraryError("course-directory-conflict");
  }
}

async function readBounded(filePath: string, maximum: number): Promise<Buffer> {
  const info = await lstat(filePath);
  if (!info.isFile() || info.isSymbolicLink() || info.size > maximum) throw new CourseLibraryError("unsafe-or-large-file");
  return readFile(filePath);
}

async function recoverInterruptedCourseState(courseRoot: string): Promise<void> {
  const metadataDirectory = await verifiedCourseSubdirectory(courseRoot, ".weibei");
  const targetPath = path.join(metadataDirectory.absolutePath, "course-state.json");
  try {
    await recoverAtomicReplace(targetPath, metadataDirectory);
  } catch (error) {
    if (error instanceof FileWriteConflictError) {
      throw new CourseLibraryError("portable-state-conflict");
    }
    throw error;
  }
  await assertVerifiedDirectory(metadataDirectory);
}

async function assertCreatedCourseDirectories(
  directories: readonly VerifiedDirectoryIdentity[],
): Promise<void> {
  for (const directory of directories) {
    await assertVerifiedDirectory(directory);
  }
}

async function rollbackExclusiveCourseCreation(
  directories: readonly VerifiedDirectoryIdentity[],
  files: readonly CreatedCourseFile[],
): Promise<void> {
  try {
    await assertCreatedCourseDirectories(directories);
  } catch {
    return;
  }

  for (const file of [...files].reverse()) {
    try {
      await assertCreatedCourseDirectories(directories);
      await assertVerifiedDirectory(file.parentDirectory);
      const info = await lstat(file.absolutePath, { bigint: true });
      if (
        !info.isFile()
        || info.isSymbolicLink()
        || info.dev !== file.dev
        || info.ino !== file.ino
        || info.size !== file.size
        || info.mtimeNs !== file.mtimeNs
        || await sha256File(file.absolutePath) !== file.digest
      ) {
        return;
      }
      await assertCreatedCourseDirectories(directories);
      await assertVerifiedDirectory(file.parentDirectory);
      await rm(file.absolutePath);
    } catch {
      // Preserve the incomplete course if any identity becomes ambiguous.
      return;
    }
  }

  for (const directory of [...directories].reverse()) {
    try {
      const info = await lstat(directory.absolutePath, { bigint: true });
      if (
        !info.isDirectory()
        || info.isSymbolicLink()
        || info.dev !== directory.dev
        || info.ino !== directory.ino
      ) {
        return;
      }
      // rmdir is intentionally non-recursive: unexpected user content makes
      // cleanup fail closed and remain available for reconciliation.
      await rmdir(directory.absolutePath);
    } catch {
      return;
    }
  }
}

async function rollbackUnregisteredCourseFiles(
  course: PortableCourse,
  createdFiles: readonly CreatedCourseFile[],
): Promise<void> {
  if (createdFiles.length === 0) return;
  for (const created of createdFiles) {
    try {
      await assertVerifiedDirectory(created.parentDirectory);
      if (await courseStateRegistersPath(course, created.relativePath) !== false) continue;
      const info = await lstat(created.absolutePath, { bigint: true });
      if (!info.isFile() || info.isSymbolicLink()) continue;
      if (
        info.dev !== created.dev
        || info.ino !== created.ino
        || info.size !== created.size
        || info.mtimeNs !== created.mtimeNs
      ) continue;
      if (await sha256File(created.absolutePath) !== created.digest) continue;
      // Hashing can take long enough for Finder/iCloud/another process to
      // register the exact path. Re-read immediately before deletion; an
      // unreadable or registered state always preserves the file.
      if (await courseStateRegistersPath(course, created.relativePath) !== false) continue;
      await assertVerifiedDirectory(created.parentDirectory);
      await rm(created.absolutePath);
    } catch {
      // Rollback is best-effort and never follows a replacement.
    }
  }
}

async function courseStateRegistersPath(
  course: PortableCourse,
  relativePath: string,
): Promise<boolean | null> {
  try {
    const state = asObject(parseSwiftJSON(
      (await readBounded(course.statePath, COURSE_FILE_LIMIT)).toString("utf8"),
    ));
    const targetKey = windowsCollisionKey(relativePath);
    return portableItemRecords(state).some((item) =>
      windowsCollisionKey(validatePortableRelativePath(
        requiredString(item.courseRelativePath, "courseRelativePath"),
      )) === targetKey);
  } catch {
    return null;
  }
}

function uniqueNameInSet(requested: string, occupied: ReadonlySet<string>): string {
  if (!occupied.has(windowsCollisionKey(requested))) return requested;
  const extension = path.extname(requested);
  const stem = path.basename(requested, extension);
  for (let index = 2; index < 10_000; index += 1) {
    const candidate = `${stem} ${index}${extension}`;
    if (!occupied.has(windowsCollisionKey(candidate))) return candidate;
  }
  throw new CourseLibraryError("name-space-exhausted");
}

function assertNoWindowsNameCollisions(names: readonly string[]): void {
  const seen = new Set<string>();
  for (const name of names) {
    const key = windowsCollisionKey(name);
    if (seen.has(key)) throw new CourseLibraryError("windows-path-collision", name);
    seen.add(key);
  }
}

function assertNoDuplicateCourseIDs(courses: readonly CourseSummary[]): void {
  const seen = new Set<string>();
  for (const course of courses) {
    const key = course.id.toLocaleLowerCase("en-US");
    if (seen.has(key)) throw new CourseLibraryError("duplicate-course-id", course.id);
    seen.add(key);
  }
}

function windowsCollisionKey(value: string): string {
  return value.normalize("NFC").toLocaleLowerCase("en-US").replace(/[. ]+$/u, "");
}

function sameFilesystemPath(left: string, right: string): boolean {
  return path.resolve(left).toLocaleLowerCase("en-US")
    === path.resolve(right).toLocaleLowerCase("en-US");
}

function asObject(value: unknown): SwiftJSONObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new CourseLibraryError("invalid-portable-state");
  return value as SwiftJSONObject;
}
function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value) throw new CourseLibraryError("invalid-portable-state", field);
  return value;
}
function numberValue(value: unknown): number {
  if (typeof value === "number") return value;
  if (typeof value === "bigint") return Number(value);
  throw new CourseLibraryError("invalid-portable-state");
}
function bigintValue(value: unknown): bigint {
  if (typeof value === "bigint") return value;
  if (typeof value === "number" && Number.isSafeInteger(value)) return BigInt(value);
  throw new CourseLibraryError("invalid-portable-state");
}
function requireIntegerRange(value: unknown, minimum: bigint, maximum: bigint): bigint {
  const integer = typeof value === "bigint"
    ? value
    : typeof value === "number" && Number.isSafeInteger(value)
      ? BigInt(value)
      : null;
  if (integer === null || integer < minimum || integer > maximum) {
    throw new CourseLibraryError("invalid-portable-state");
  }
  return integer;
}
function requirePortableRevisionCanAdvance(value: unknown): bigint {
  const revision = requireIntegerRange(value, 0n, swiftUIntMaximum);
  if (revision === swiftUIntMaximum) {
    throw new CourseLibraryError("portable-revision-overflow");
  }
  return revision;
}
function validateSwiftDate(value: unknown): void {
  if (typeof value !== "number" && typeof value !== "bigint") {
    throw new CourseLibraryError("invalid-portable-state");
  }
  if (!Number.isFinite(dateFromSwiftReferenceSeconds(value).getTime())) {
    throw new CourseLibraryError("invalid-portable-state");
  }
}
function safeNumber(value: unknown): number {
  const result = numberValue(value);
  return Number.isSafeInteger(result) && result >= 0 ? result : Number.MAX_SAFE_INTEGER;
}
function dateValue(value: unknown): Date {
  if (typeof value !== "number" && typeof value !== "bigint") throw new CourseLibraryError("invalid-portable-state");
  return dateFromSwiftReferenceSeconds(value);
}
function isUUID(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function sameUUID(left: string, right: string): boolean {
  return isUUID(left)
    && isUUID(right)
    && left.toLocaleLowerCase("en-US") === right.toLocaleLowerCase("en-US");
}
function isAlreadyExistsError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error && error.code === "EEXIST";
}
function mediaTypeFor(kind: StudyItemKind): DocumentPayload["mediaType"] {
  return { markdown: "text/markdown", text: "text/plain", html: "text/html", pdf: "application/pdf" }[kind] as DocumentPayload["mediaType"];
}
