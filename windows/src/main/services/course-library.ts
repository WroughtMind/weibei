import { randomUUID } from "node:crypto";
import {
  lstat,
  mkdir,
  readFile,
  readdir,
  realpath,
  stat,
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
  atomicWriteVerified,
  copyFileVerified,
  resolveExistingInside,
  safeFileName,
  sha256,
  sha256File,
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
};

interface PortableCourse {
  rootPath: string;
  manifestPath: string;
  statePath: string;
  courseID: string;
  state: SwiftJSONObject;
  digest: string;
}

export interface CourseLibraryOptions {
  rootPath: string;
  sessionsForCourse?: (courseID: string) => Promise<CourseDetail["sessions"]>;
}

export interface OpenCourseItem {
  payload: Omit<DocumentPayload, "documentGrantUrl">;
  absolutePath: string;
}

export class CourseLibrary {
  readonly rootPath: string;
  private readonly sessionsForCourse: NonNullable<CourseLibraryOptions["sessionsForCourse"]>;
  private queue: Promise<void> = Promise.resolve();

  constructor(options: CourseLibraryOptions | string) {
    this.rootPath = path.resolve(typeof options === "string" ? options : options.rootPath);
    this.sessionsForCourse = typeof options === "string" || !options.sessionsForCourse
      ? async () => []
      : options.sessionsForCourse;
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
    return summaries
      .filter((summary): summary is CourseSummary => summary !== null)
      .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt) || left.title.localeCompare(right.title, "zh-Hans"));
  }

  async detail(courseID: string, selection?: {
    activeItemId?: string | null;
    activeNoteId?: string | null;
    activeSessionId?: string | null;
  }): Promise<CourseDetail> {
    const course = await this.findCourse(courseID);
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
  }

  async createCourse(title: string, colorIndex = 0): Promise<CourseSummary> {
    return this.runExclusive(async () => {
      await this.ensureLayout();
      const cleanTitle = title.trim();
      if (!cleanTitle || cleanTitle.length > 120) throw new CourseLibraryError("invalid-title");
      const folderName = await this.uniqueFileName(safeFileName(cleanTitle, "新课程"));
      const rootPath = path.join(this.rootPath, folderName);
      const metadataPath = path.join(rootPath, ".weibei");
      await Promise.all([
        mkdir(path.join(rootPath, COURSE_MATERIALS_DIRECTORY), { recursive: true }),
        mkdir(path.join(rootPath, COURSE_NOTES_DIRECTORY), { recursive: true }),
        mkdir(metadataPath, { recursive: true }),
      ]);
      const courseID = randomUUID();
      const now = new Date();
      const manifest = { courseID, schemaVersion: 1 };
      const state = emptyPortableState(courseID, cleanTitle, colorIndex, now);
      await atomicWriteVerified(
        path.join(rootPath, COURSE_MANIFEST_RELATIVE_PATH),
        stringifySwiftJSON(manifest, { sortKeys: true }),
      );
      await atomicWriteVerified(
        path.join(rootPath, COURSE_STATE_RELATIVE_PATH),
        stringifySwiftJSON(state, { sortKeys: true }),
      );
      return summaryFromPortable(await this.loadCourseRoot(rootPath));
    });
  }

  async importFiles(courseID: string, sourcePaths: readonly string[]): Promise<StudyItem[]> {
    return this.runExclusive(async () => {
      if (sourcePaths.length === 0) return [];
      const course = await this.findCourse(courseID);
      const existingItems = portableItemRecords(course.state);
      const imported: SwiftJSONObject[] = [];
      const occupiedNames = new Set(
        (await readdir(path.join(course.rootPath, COURSE_MATERIALS_DIRECTORY))).map(windowsCollisionKey),
      );
      for (const sourcePath of sourcePaths) {
        const source = path.resolve(sourcePath);
        const extension = path.extname(source).toLocaleLowerCase("en-US");
        const kind = supportedExtensions[extension];
        if (!kind) throw new CourseLibraryError("unsupported-file", path.basename(source));
        const before = await stableFileSnapshot(source);
        if (before.byteLength > COURSE_FILE_LIMIT) throw new CourseLibraryError("file-too-large", path.basename(source));
        let name = safeFileName(path.basename(source), `未命名${extension}`);
        name = uniqueNameInSet(name, occupiedNames);
        occupiedNames.add(windowsCollisionKey(name));
        const relativePath = `${COURSE_MATERIALS_DIRECTORY}/${name}`;
        const target = path.join(course.rootPath, COURSE_MATERIALS_DIRECTORY, name);
        const digest = await copyFileVerified(source, target);
        const after = await stableFileSnapshot(source);
        if (before.digest !== after.digest || before.byteLength !== after.byteLength || before.mtimeNs !== after.mtimeNs) {
          throw new CourseLibraryError("source-changed", path.basename(source));
        }
        const targetStats = await stat(target, { bigint: true });
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
    });
  }

  async createNote(courseID: string, title: string): Promise<StudyItem> {
    return this.runExclusive(async () => {
      const course = await this.findCourse(courseID);
      const cleanTitle = title.trim();
      if (!cleanTitle || cleanTitle.length > 120) throw new CourseLibraryError("invalid-title");
      const directory = path.join(course.rootPath, COURSE_NOTES_DIRECTORY);
      const existing = new Set((await readdir(directory)).map(windowsCollisionKey));
      const name = uniqueNameInSet(`${safeFileName(cleanTitle, "无题笔记")}.md`, existing);
      const target = path.join(directory, name);
      const initial = `# ${cleanTitle}\n\n`;
      const digest = await atomicWriteVerified(target, initial);
      const targetStats = await stat(target, { bigint: true });
      const record: SwiftJSONObject = {
        itemID: `imported:${randomUUID().toLocaleLowerCase("en-US")}`,
        title: cleanTitle,
        kind: "markdown",
        isNotebookNote: true,
        appearsInMaterials: false,
        courseRelativePath: `${COURSE_NOTES_DIRECTORY}/${name}`,
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
    });
  }

  async openItem(courseID: string, itemID: string): Promise<OpenCourseItem> {
    const course = await this.findCourse(courseID);
    const raw = portableItemRecords(course.state).find((entry) => entry.itemID === itemID);
    if (!raw) throw new CourseLibraryError("item-not-found");
    const relativePath = requiredString(raw.courseRelativePath, "courseRelativePath");
    const portablePath = validatePortableRelativePath(relativePath);
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
    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith(".")) continue;
      try {
        const course = await this.loadCourseRoot(path.join(this.rootPath, entry.name));
        if (course.courseID === courseID) return course;
      } catch {
        // A damaged sibling course must not block the requested course.
      }
    }
    throw new CourseLibraryError("course-not-found");
  }

  private async loadCourseRoot(candidateRoot: string): Promise<PortableCourse> {
    const [canonicalLibrary, rootPath] = await Promise.all([realpath(this.rootPath), realpath(candidateRoot)]);
    const relative = path.relative(canonicalLibrary, rootPath);
    if (!relative || path.isAbsolute(relative) || relative.startsWith(`..${path.sep}`) || relative === "..") {
      throw new CourseLibraryError("unsafe-course-root");
    }
    const manifestPath = path.join(rootPath, COURSE_MANIFEST_RELATIVE_PATH);
    const statePath = path.join(rootPath, COURSE_STATE_RELATIVE_PATH);
    const [manifestBytes, stateBytes] = await Promise.all([
      readBounded(manifestPath, 1024 * 1024),
      readBounded(statePath, COURSE_FILE_LIMIT),
    ]);
    const manifest = asObject(parseSwiftJSON(manifestBytes.toString("utf8")));
    const state = asObject(parseSwiftJSON(stateBytes.toString("utf8")));
    const courseID = requiredString(manifest.courseID, "courseID");
    if (!isUUID(courseID) || manifest.schemaVersion !== 1 || state.courseID !== courseID || ![1, 2].includes(numberValue(state.schemaVersion))) {
      throw new CourseLibraryError("invalid-portable-state");
    }
    if (!Array.isArray(state.items) || !asObject(state.metadata)) throw new CourseLibraryError("invalid-portable-state");
    validatePortableItems(state.items, rootPath);
    return { rootPath, manifestPath, statePath, courseID, state, digest: sha256(stateBytes) };
  }

  private async saveCourseState(course: PortableCourse, items: SwiftJSONObject[]): Promise<void> {
    const currentBytes = await readBounded(course.statePath, COURSE_FILE_LIMIT);
    if (sha256(currentBytes) !== course.digest) throw new CourseLibraryError("portable-state-conflict");
    const current = asObject(parseSwiftJSON(currentBytes.toString("utf8")));
    const currentRevision = bigintValue(current.revision);
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
    await atomicWriteVerified(course.statePath, serialized);
    const reread = await readFile(course.statePath);
    if (sha256(reread) !== sha256(serialized)) throw new CourseLibraryError("write-verification-failed");
  }

  private async uniqueFileName(stem: string): Promise<string> {
    const occupied = new Set((await readdir(this.rootPath)).map(windowsCollisionKey));
    return uniqueNameInSet(stem, occupied);
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
    const relativePath = validatePortableRelativePath(requiredString(item.courseRelativePath, "courseRelativePath"));
    if (ids.has(id)) throw new CourseLibraryError("duplicate-item-id");
    if (paths.has(relativePath)) continue; // matches mac portable normalization
    const collision = windowsCollisionKey(relativePath);
    if (collisionKeys.has(collision)) throw new CourseLibraryError("windows-path-collision", relativePath);
    const first = relativePath.split("/")[0];
    if (first !== COURSE_MATERIALS_DIRECTORY && first !== COURSE_NOTES_DIRECTORY) throw new CourseLibraryError("invalid-item-role");
    const kind = supportedExtensions[path.extname(relativePath).toLocaleLowerCase("en-US")];
    if (!kind || item.kind !== kind) throw new CourseLibraryError("invalid-item-kind");
    if (item.isNotebookNote === true && kind !== "markdown") throw new CourseLibraryError("invalid-note-kind");
    ids.add(id); paths.add(relativePath); collisionKeys.add(collision);
    void rootPath;
  }
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

async function readBounded(filePath: string, maximum: number): Promise<Buffer> {
  const info = await lstat(filePath);
  if (!info.isFile() || info.isSymbolicLink() || info.size > maximum) throw new CourseLibraryError("unsafe-or-large-file");
  return readFile(filePath);
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

function windowsCollisionKey(value: string): string {
  return value.normalize("NFC").toLocaleLowerCase("en-US").replace(/[. ]+$/u, "");
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
function safeNumber(value: unknown): number {
  const result = numberValue(value);
  return Number.isSafeInteger(result) && result >= 0 ? result : Number.MAX_SAFE_INTEGER;
}
function dateValue(value: unknown): Date {
  if (typeof value !== "number" && typeof value !== "bigint") throw new CourseLibraryError("invalid-portable-state");
  return dateFromSwiftReferenceSeconds(value);
}
function isUUID(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function mediaTypeFor(kind: StudyItemKind): DocumentPayload["mediaType"] {
  return { markdown: "text/markdown", text: "text/plain", html: "text/html", pdf: "application/pdf" }[kind] as DocumentPayload["mediaType"];
}
