import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import {
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  COURSE_MANIFEST_RELATIVE_PATH,
  COURSE_MATERIALS_DIRECTORY,
  COURSE_NOTES_DIRECTORY,
  COURSE_STATE_RELATIVE_PATH,
  CourseLibrary,
  CourseLibraryError,
} from "../src/main/services/course-library";
import { sha256 } from "../src/main/services/file-utils";
import {
  dateFromSwiftReferenceSeconds,
  parseSwiftJSON,
  stringifySwiftJSON,
  swiftReferenceSecondsFromDate,
  type SwiftJSONObject,
} from "../src/main/services/swift-codec";

test("createCourse writes a Swift-decodable v1 manifest and portable v2 state", async () => {
  await withLibrary(async ({ library }) => {
    const summary = await library.createCourse("碑学入门", 3);
    const manifest = await readSwiftObject(
      path.join(summary.rootPath, COURSE_MANIFEST_RELATIVE_PATH),
    );
    const state = await readSwiftObject(
      path.join(summary.rootPath, COURSE_STATE_RELATIVE_PATH),
    );

    assert.equal(manifest.courseID, summary.id);
    assert.equal(manifest.schemaVersion, 1);
    assert.equal(state.courseID, summary.id);
    assert.equal(state.schemaVersion, 2);
    assert.equal(state.revision, 0);
    assertSwiftDate(state.savedAt);
    const metadata = objectValue(state.metadata);
    assert.equal(metadata.title, "碑学入门");
    assert.equal(metadata.colorIndex, 3);
    assertSwiftDate(metadata.createdAt);
    assertSwiftDate(metadata.updatedAt);
    assert.deepEqual(state.items, []);
    assert.deepEqual(state.studySessions, []);
    assert.deepEqual(state.noteSourceLinks, []);
    assert.deepEqual(state.studyLocationsByItemID, {});
    assert.deepEqual(state.pendingNoteDrafts, []);

    // The same lossless codec must be able to read its own sorted-key output.
    assert.deepEqual(
      parseSwiftJSON(stringifySwiftJSON(state, { sortKeys: true })),
      state,
    );
    assert.deepEqual(
      (await library.listCourses()).map((course) => course.id),
      [summary.id],
    );
    assert.deepEqual(
      (await readdir(summary.rootPath)).sort(),
      [".weibei", COURSE_MATERIALS_DIRECTORY, COURSE_NOTES_DIRECTORY].sort(),
    );
  });
});

test("Markdown import records a stable byte snapshot and increments portable revision", async () => {
  await withLibrary(async ({ library, directory }) => {
    const course = await library.createCourse("导入课");
    const sourceDirectory = path.join(directory, "incoming");
    await mkdir(sourceDirectory);
    const sourcePath = path.join(sourceDirectory, "拓片.md");
    const sourceBytes = Buffer.from("# 拓片\n\n龙门二十品 e\u0301 👨‍👩‍👧‍👦\n", "utf8");
    await writeFile(sourcePath, sourceBytes);
    const before = await lstat(sourcePath, { bigint: true });

    const [item] = await library.importFiles(course.id, [sourcePath]);
    assert.ok(item);
    assert.equal(item.kind, "markdown");
    assert.equal(item.isNotebookNote, true);
    assert.equal(item.appearsInMaterials, true);
    assert.equal(item.relativePath, `${COURSE_MATERIALS_DIRECTORY}/拓片.md`);
    assert.equal(item.contentDigest, sha256(sourceBytes));
    assert.deepEqual(await readFile(sourcePath), sourceBytes);
    const after = await lstat(sourcePath, { bigint: true });
    assert.equal(after.size, before.size);
    assert.equal(after.mtimeNs, before.mtimeNs);

    const state = await readSwiftObject(
      path.join(course.rootPath, COURSE_STATE_RELATIVE_PATH),
    );
    assert.equal(state.revision, 1);
    assertSwiftDate(state.savedAt);
    const raw = arrayObjects(state.items)[0];
    assert.equal(raw.itemID, item.id);
    assert.equal(raw.courseRelativePath, item.relativePath);
    assert.deepEqual(raw.storage, { kind: "courseOwned" });
    assert.equal(raw.contentRevision, 1);
    assert.equal(raw.contentDigest, sha256(sourceBytes));
    assert.equal(raw.fileByteCount, sourceBytes.byteLength);
    assert.equal(typeof raw.fileModificationTimeNanoseconds, "bigint");
    assertSwiftDate(raw.membershipCreatedAt);

    const opened = await library.openItem(course.id, item.id);
    assert.equal(opened.payload.content, sourceBytes.toString("utf8"));
    assert.equal(opened.payload.digest, sha256(sourceBytes));
    assert.deepEqual(await readFile(opened.absolutePath), sourceBytes);
  });
});

test("case-folded and NFC-equivalent course folder collisions are blocked", async () => {
  await withLibrary(async ({ rootPath }) => {
    await mkdir(path.join(rootPath, "Course"), { recursive: true });
    await mkdir(path.join(rootPath, "course"), { recursive: true });
    const names = await readdir(rootPath);
    if (!names.includes("Course") || !names.includes("course")) return;
    const library = new CourseLibrary(rootPath);
    await assert.rejects(
      library.listCourses(),
      isCourseError("windows-path-collision"),
    );
  });

  await withLibrary(async ({ rootPath }) => {
    const composed = "Café";
    const decomposed = "Cafe\u0301";
    await mkdir(path.join(rootPath, composed), { recursive: true });
    await mkdir(path.join(rootPath, decomposed), { recursive: true });
    const names = await readdir(rootPath);
    if (!names.includes(composed) || !names.includes(decomposed)) return;
    const library = new CourseLibrary(rootPath);
    await assert.rejects(
      library.listCourses(),
      isCourseError("windows-path-collision"),
    );
  });
});

test("mac portable states with case or NFC item collisions are not adopted or rewritten", async () => {
  await withLibrary(async ({ rootPath }) => {
    const caseID = randomUUID();
    const nfcID = randomUUID();
    const caseRoot = await writeMacCourse(rootPath, {
      folderName: "Case Collision",
      courseID: caseID,
      title: "大小写冲突",
      items: [
        portableItem("case-a", `${COURSE_MATERIALS_DIRECTORY}/A.md`),
        portableItem("case-b", `${COURSE_MATERIALS_DIRECTORY}/a.md`),
      ],
    });
    const nfcRoot = await writeMacCourse(rootPath, {
      folderName: "NFC Collision",
      courseID: nfcID,
      title: "NFC 冲突",
      items: [
        portableItem("nfc-a", `${COURSE_MATERIALS_DIRECTORY}/Café.md`),
        portableItem("nfc-b", `${COURSE_MATERIALS_DIRECTORY}/Cafe\u0301.md`),
      ],
    });
    const caseStatePath = path.join(caseRoot, COURSE_STATE_RELATIVE_PATH);
    const nfcStatePath = path.join(nfcRoot, COURSE_STATE_RELATIVE_PATH);
    const [caseBefore, nfcBefore] = await Promise.all([
      readFile(caseStatePath),
      readFile(nfcStatePath),
    ]);

    const library = new CourseLibrary(rootPath);
    assert.deepEqual(await library.listCourses(), []);
    await assert.rejects(library.detail(caseID), isCourseError("course-not-found"));
    await assert.rejects(library.detail(nfcID), isCourseError("course-not-found"));
    assert.deepEqual(await readFile(caseStatePath), caseBefore);
    assert.deepEqual(await readFile(nfcStatePath), nfcBefore);
  });
});

test("createNote writes canonical Markdown under 笔记 and registers a portable note", async () => {
  await withLibrary(async ({ library }) => {
    const course = await library.createCourse("笔记课");
    const note = await library.createNote(course.id, "石门铭");
    assert.equal(note.kind, "markdown");
    assert.equal(note.isNotebookNote, true);
    assert.equal(note.appearsInMaterials, false);
    assert.equal(note.relativePath, `${COURSE_NOTES_DIRECTORY}/石门铭.md`);

    const notePath = path.join(course.rootPath, COURSE_NOTES_DIRECTORY, "石门铭.md");
    assert.equal(await readFile(notePath, "utf8"), "# 石门铭\n\n");
    const state = await readSwiftObject(
      path.join(course.rootPath, COURSE_STATE_RELATIVE_PATH),
    );
    assert.equal(state.revision, 1);
    const raw = arrayObjects(state.items)[0];
    assert.equal(raw.itemID, note.id);
    assert.equal(raw.courseRelativePath, note.relativePath);
    assert.equal(raw.isNotebookNote, true);
    assert.equal(raw.appearsInMaterials, false);
    assert.deepEqual(raw.storage, { kind: "courseOwned" });
    assert.equal(raw.contentDigest, sha256("# 石门铭\n\n"));
  });
});

test("unsafe traversal, leaf symlinks, and symlink import sources are rejected", async (t) => {
  await withLibrary(async ({ library, rootPath, directory }) => {
    const traversalID = randomUUID();
    await writeMacCourse(rootPath, {
      folderName: "Traversal",
      courseID: traversalID,
      title: "越界课程",
      items: [portableItem("escape", `${COURSE_MATERIALS_DIRECTORY}/../笔记/escape.md`)],
    });
    assert.equal(
      (await library.listCourses()).some((course) => course.id === traversalID),
      false,
    );

    const course = await library.createCourse("链接课");
    const realPath = path.join(course.rootPath, COURSE_MATERIALS_DIRECTORY, "real.md");
    const linkPath = path.join(course.rootPath, COURSE_MATERIALS_DIRECTORY, "link.md");
    await writeFile(realPath, "real body", "utf8");
    try {
      await symlink("real.md", linkPath);
    } catch (error) {
      if (process.platform === "win32") {
        t.diagnostic(`symlink assertions skipped: ${String(error)}`);
        return;
      }
      throw error;
    }
    const statePath = path.join(course.rootPath, COURSE_STATE_RELATIVE_PATH);
    const state = await readSwiftObject(statePath);
    state.items = [
      {
        ...portableItem("link-item", `${COURSE_MATERIALS_DIRECTORY}/link.md`),
        contentDigest: sha256("real body"),
        fileByteCount: 9,
      },
    ];
    await writeFile(statePath, stringifySwiftJSON(state, { sortKeys: true }), "utf8");
    assert.equal((await library.detail(course.id)).items.length, 1);
    await assert.rejects(library.openItem(course.id, "link-item"), isCourseError("unsafe-item"));

    const sourceTarget = path.join(directory, "source-target.md");
    const sourceLink = path.join(directory, "source-link.md");
    await writeFile(sourceTarget, "source", "utf8");
    await symlink(sourceTarget, sourceLink);
    const beforeImport = await readFile(statePath);
    await assert.rejects(
      library.importFiles(course.id, [sourceLink]),
      isCourseError("not-regular-file"),
    );
    assert.deepEqual(await readFile(statePath), beforeImport);
  });
});

test("an existing mac-style course round-trips unknown fields and lossless revision", async () => {
  await withLibrary(async ({ rootPath, directory }) => {
    const courseID = randomUUID().toUpperCase();
    const legacyBytes = Buffer.from("# 旧资料\n\n不可丢失。\n", "utf8");
    const legacyDigest = sha256(legacyBytes);
    const legacyRevision = 9_007_199_254_740_993n;
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Mac Course",
      courseID,
      title: "Mac 旧课程",
      revision: legacyRevision,
      items: [
        {
          ...portableItem("legacy-item", `${COURSE_MATERIALS_DIRECTORY}/旧资料.md`),
          contentRevision: 9_007_199_254_740_995n,
          contentDigest: legacyDigest,
          fileByteCount: legacyBytes.byteLength,
          futureItemField: { raw: "keep-item" },
        },
      ],
      extraState: {
        futureStateField: { raw: "keep-state" },
        studySessions: [{ legacy: "must-be-removed-in-v2" }],
      },
      extraMetadata: { futureMetadataField: "keep-metadata" },
    });
    await writeFile(
      path.join(courseRoot, COURSE_MATERIALS_DIRECTORY, "旧资料.md"),
      legacyBytes,
    );
    const manifestPath = path.join(courseRoot, COURSE_MANIFEST_RELATIVE_PATH);
    const manifestBefore = await readFile(manifestPath);
    const library = new CourseLibrary(rootPath);
    const listed = await library.listCourses();
    assert.equal(listed.length, 1);
    assert.equal(listed[0].id, courseID);
    assert.equal((await library.detail(courseID)).items[0].id, "legacy-item");

    const sourcePath = path.join(directory, "新增.md");
    await writeFile(sourcePath, "# 新增\n", "utf8");
    await library.importFiles(courseID, [sourcePath]);

    assert.deepEqual(await readFile(manifestPath), manifestBefore);
    assert.deepEqual(
      await readFile(path.join(courseRoot, COURSE_MATERIALS_DIRECTORY, "旧资料.md")),
      legacyBytes,
    );
    const roundTripped = await readSwiftObject(
      path.join(courseRoot, COURSE_STATE_RELATIVE_PATH),
    );
    assert.equal(roundTripped.revision, legacyRevision + 1n);
    assert.deepEqual(roundTripped.futureStateField, { raw: "keep-state" });
    assert.deepEqual(roundTripped.studySessions, []);
    const metadata = objectValue(roundTripped.metadata);
    assert.equal(metadata.futureMetadataField, "keep-metadata");
    const items = arrayObjects(roundTripped.items);
    assert.equal(items.length, 2);
    const legacy = items.find((item) => item.itemID === "legacy-item")!;
    assert.equal(legacy.contentRevision, 9_007_199_254_740_995n);
    assert.deepEqual(legacy.futureItemField, { raw: "keep-item" });
  });
});

interface LibraryFixture {
  directory: string;
  rootPath: string;
  library: CourseLibrary;
}

async function withLibrary(
  operation: (fixture: LibraryFixture) => Promise<void>,
): Promise<void> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-course-library-"));
  const rootPath = path.join(directory, "library");
  await mkdir(rootPath);
  try {
    await operation({
      directory,
      rootPath,
      library: new CourseLibrary(rootPath),
    });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

interface MacCourseOptions {
  folderName: string;
  courseID: string;
  title: string;
  revision?: number | bigint;
  items?: SwiftJSONObject[];
  extraState?: SwiftJSONObject;
  extraMetadata?: SwiftJSONObject;
}

async function writeMacCourse(
  libraryRoot: string,
  options: MacCourseOptions,
): Promise<string> {
  const root = path.join(libraryRoot, options.folderName);
  await Promise.all([
    mkdir(path.join(root, ".weibei"), { recursive: true }),
    mkdir(path.join(root, COURSE_MATERIALS_DIRECTORY), { recursive: true }),
    mkdir(path.join(root, COURSE_NOTES_DIRECTORY), { recursive: true }),
  ]);
  const fixed = new Date("2025-01-02T03:04:05.000Z");
  const manifest = { courseID: options.courseID, schemaVersion: 1 };
  const state: SwiftJSONObject = {
    courseID: options.courseID,
    schemaVersion: 2,
    revision: options.revision ?? 0,
    savedAt: swiftReferenceSecondsFromDate(fixed),
    metadata: {
      title: options.title,
      colorIndex: 1,
      createdAt: swiftReferenceSecondsFromDate(fixed),
      updatedAt: swiftReferenceSecondsFromDate(fixed),
      ...options.extraMetadata,
    },
    items: options.items ?? [],
    studySessions: [],
    learningMemoryState: null,
    courseKnowledgeProfile: null,
    noteSourceLinks: [],
    studyLocationsByItemID: {},
    resumePoint: null,
    pendingNoteDrafts: [],
    ...options.extraState,
  };
  await Promise.all([
    writeFile(
      path.join(root, COURSE_MANIFEST_RELATIVE_PATH),
      stringifySwiftJSON(manifest, { sortKeys: true }),
      "utf8",
    ),
    writeFile(
      path.join(root, COURSE_STATE_RELATIVE_PATH),
      stringifySwiftJSON(state, { sortKeys: true }),
      "utf8",
    ),
  ]);
  return root;
}

function portableItem(itemID: string, courseRelativePath: string): SwiftJSONObject {
  const fixed = new Date("2025-01-02T03:04:05.000Z");
  return {
    itemID,
    title: path.basename(courseRelativePath, path.extname(courseRelativePath)),
    kind: "markdown",
    isNotebookNote: true,
    appearsInMaterials: true,
    courseRelativePath,
    storage: { kind: "courseOwned" },
    contentRevision: 1,
    contentDigest: null,
    fileByteCount: null,
    fileModificationTimeNanoseconds: null,
    membershipCreatedAt: swiftReferenceSecondsFromDate(fixed),
  };
}

async function readSwiftObject(filePath: string): Promise<SwiftJSONObject> {
  return objectValue(parseSwiftJSON(await readFile(filePath, "utf8")));
}

function objectValue(value: unknown): SwiftJSONObject {
  assert.ok(value && typeof value === "object" && !Array.isArray(value));
  return value as SwiftJSONObject;
}

function arrayObjects(value: unknown): SwiftJSONObject[] {
  assert.ok(Array.isArray(value));
  return value.map(objectValue);
}

function assertSwiftDate(value: unknown): void {
  assert.ok(typeof value === "number" || typeof value === "bigint");
  assert.ok(Number.isFinite(dateFromSwiftReferenceSeconds(value).getTime()));
}

function isCourseError(code: string): (error: unknown) => boolean {
  return (error) => error instanceof CourseLibraryError && error.code === code;
}
